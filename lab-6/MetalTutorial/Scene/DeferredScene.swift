import Metal
import MetalKit
import simd

final class DeferredScene: RenderScene {
    struct EngineParticleTransform {
        var position: simd_float3 = simd_float3(0.0, 180.0, 0.0)
        var rotation: simd_float3 = simd_float3(0.0, -.pi / 2.0, 0.0)

        var direction: simd_float3 {
            var rotationMatrix = matrix_identity_float4x4
            rotateMatrix(matrix: &rotationMatrix, rotation: rotation)
            let rotated = rotationMatrix * simd_float4(0.0, 0.0, -1.0, 0.0)
            return simd_normalize(simd_float3(rotated.x, rotated.y, rotated.z))
        }
    }

    struct Settings {
        var planePosition: simd_float3 = simd_float3(-50.0, 450.0, 200.0)
        var planeSize: simd_float2 = simd_float2(2000.0, 600.0)
        var planePatchCenter: simd_float2 = simd_float2(0.0, -220.0)
        var planePatchResolution: Int = 8
        var planeMinTessellationFactor: Float = 1.0
        var planeMaxTessellationFactor: Float = 32.0
        var planeMinDistance: Float = 200.0
        var planeMaxDistance: Float = 1800.0
        var planeDisplacementScale: Float = 9.0
        var planeUVScale: simd_float2 = simd_float2(repeating: 1.35)
        var planeNormalStrength: Float = 0.55
        var planeWaveAmplitude: Float = 2.6
        var planeWaveFrequency: Float = 13.0
        var planeWaveSpeed: Float = 1.3
        var planeSpecularStrength: Float = 0.22
        var planeRoughness: Float = 0.88
        var objectInstanceCount: Int = 2000
        var engineParticles: EngineParticleTransform = EngineParticleTransform()
        var collisionTestSurfaceEnabled: Bool = true
        var collisionTestSurfacePosition: simd_float3 = simd_float3(430.0, 180.0, 0.0)
        var collisionTestSurfaceRotation: simd_float3 = simd_float3(0.0, 0.0, toRadians(from: -28.0))
        var collisionTestSurfaceScale: simd_float3 = simd_float3(18.0, 260.0, 340.0)
    }

    let ambientLight: MtlAmbientLight
    let directionalLight: MtlDirectionalLight
    let pointLights: [MtlPointLight]
    let spotLights: [MtlSpotLight]
    let geometryRendererKind: GeometryRendererKind = .deferredHybrid
    let prefersOrbitingCamera: Bool
    let preferredCameraPosition: simd_float3
    let preferredCameraYaw: Float
    let preferredCameraPitch: Float
    let sceneBounds: AABB
    let settings: Settings

    private let objects: [CullingObject]
    private let octree: Octree
    private let particleEffect: RocketEngineParticleEffect

    var hudStatus: String? {
        """
        Scene : Sponza
        Input : slider / +/- thrust
        GPU   : compute particles + depth collision
        """
    }

    var particleStatus: String? {
        particleEffect.debugStatus
    }

    init(device: MTLDevice, view: MTKView, geometryVertexDescriptor: MTLVertexDescriptor, settings: Settings = Settings()) {
        self.settings = settings
        self.particleEffect = RocketEngineParticleEffect(device: device, view: view)
        let importer = USDSceneImporter(device: device)
        let baseCubeDrawCall = GeometryPrimitives.makeCubeDrawCall(device: device)
        let planeTextures = TextureSetLoader(device: device).loadTextureSet(
            albedo: (name: "cliff_side_diff_2k", ext: "jpg"),
            normal: (name: "cliff_side_nor_2k", ext: "jpg"),
            displacement: (name: "cliff_side_disp_2k", ext: "png")
        )
        let terrain = GeometryPrimitives.makeTerrainPatch(
            device: device,
            size: settings.planeSize,
            center: settings.planePatchCenter,
            patchResolution: settings.planePatchResolution,
            minFactor: settings.planeMinTessellationFactor,
            maxFactor: settings.planeMaxTessellationFactor,
            minDistance: settings.planeMinDistance,
            maxDistance: settings.planeMaxDistance
        )
        var planeModelMatrix = matrix_identity_float4x4
        translateMatrix(matrix: &planeModelMatrix, position: settings.planePosition)
        let planeDrawCall: GeometryDrawCall = .tessellated(TessellatedGeometryDrawCall(
            controlPointBuffer: terrain.controlPointBuffer,
            patchInfoBuffer: terrain.patchInfoBuffer,
            tessellationFactorBuffer: terrain.tessellationFactorBuffer,
            patchCount: terrain.patchCount,
            tessellationBoundsMin: terrain.boundsMin,
            tessellationBoundsMax: terrain.boundsMax,
            minTessellationFactor: settings.planeMinTessellationFactor,
            maxTessellationFactor: settings.planeMaxTessellationFactor,
            minTessellationDistance: settings.planeMinDistance,
            maxTessellationDistance: settings.planeMaxDistance,
            modelMatrix: planeModelMatrix,
            displacementScale: settings.planeDisplacementScale,
            uvScale: simd_max(settings.planeUVScale * (settings.planeSize / 420.0), simd_float2(repeating: 0.001)),
            normalStrength: settings.planeNormalStrength,
            waveAmplitude: settings.planeWaveAmplitude,
            waveFrequency: settings.planeWaveFrequency,
            waveSpeed: settings.planeWaveSpeed,
            material: MaterialDrawState(
                albedoTexture: planeTextures.albedo,
                normalTexture: planeTextures.normal,
                displacementTexture: planeTextures.displacement,
                specularStrength: settings.planeSpecularStrength,
                roughness: settings.planeRoughness,
                opacity: 0.38
            )
        ))
        let planeLocalBounds = AABB(
            min: simd_float3(terrain.boundsMin.x, -settings.planeDisplacementScale - settings.planeWaveAmplitude, terrain.boundsMin.y),
            max: simd_float3(terrain.boundsMax.x, settings.planeDisplacementScale + settings.planeWaveAmplitude, terrain.boundsMax.y)
        )

        var loadedObjects: [CullingObject]
        if let geometry = importer.loadSponzaScene(vertexDescriptor: geometryVertexDescriptor) {
            loadedObjects = geometry.objects
            self.prefersOrbitingCamera = false
            self.preferredCameraPosition = simd_float3(0.0, 4.0, 15.0)
            self.preferredCameraYaw = -.pi / 2.0
            self.preferredCameraPitch = 0.0
            self.ambientLight = MtlAmbientLight(color: simd_float3(1.0, 0.98, 0.95), intensity: 0.01)
            self.directionalLight = MtlDirectionalLight(
                direction: simd_normalize(simd_float3(-0.25, -1.0, -0.15)),
                color: simd_float3(1.0, 0.98, 0.95),
                intensity: 0.02
            )
            self.pointLights = [
                MtlPointLight(position: simd_float3(-500.0, 300.0, 0.0), color: simd_float3(1.0, 0.55, 0.32), intensity: 2.0, radius: 700.0),
                MtlPointLight(position: simd_float3(0.0, 300.0, -400.0), color: simd_float3(0.35, 0.55, 1.0), intensity: 2.0, radius: 800.0),
                MtlPointLight(position: simd_float3(500.0, 300.0, 150.0), color: simd_float3(1.0, 0.8, 0.45), intensity: 2.0, radius: 700.0),
                MtlPointLight(position: simd_float3(0.0, 500.0, 600.0), color: simd_float3(0.5, 1.0, 0.8), intensity: 2.0, radius: 900.0)
            ]
            self.spotLights = [
                MtlSpotLight(position: simd_float3(-0.0, 300.0, 0.0), direction: simd_normalize(simd_float3(1.0, 0.0, 0.0)), color: simd_float3(1.0, 0.0, 0.0), intensity: 28.0, innerCos: cos(12.0 * .pi / 180.0), outerCos: cos(22.0 * .pi / 180.0), radius: 1800.0)
            ]
            print("[Renderer] Loaded Sponza geometry: \(geometry.objects.count) culling objects")
        } else {
            loadedObjects = [
                CullingObject(
                    id: 0,
                    bounds: AABB(min: simd_float3(repeating: -0.5), max: simd_float3(repeating: 0.5)),
                    drawCalls: [baseCubeDrawCall],
                    label: "Fallback Cube"
                )
            ]
            self.prefersOrbitingCamera = true
            self.preferredCameraPosition = simd_float3(0.0, 4.0, 15.0)
            self.preferredCameraYaw = -.pi / 2.0
            self.preferredCameraPitch = 0.0
            self.ambientLight = MtlAmbientLight(color: simd_float3(repeating: 1.0), intensity: 0.10)
            self.directionalLight = MtlDirectionalLight(
                direction: simd_normalize(simd_float3(-0.45, -1.0, -0.2)),
                color: simd_float3(1.0, 1.0, 1.0),
                intensity: 0.22
            )
            self.pointLights = []
            self.spotLights = []
            print("[Renderer] Loaded Deferred fallback scene: Cube")
        }

        var nextObjectID = loadedObjects.count
        let scatterObjects = Self.makeScatterObjects(
            baseDrawCall: baseCubeDrawCall,
            startID: nextObjectID,
            count: settings.objectInstanceCount
        )
        loadedObjects.append(contentsOf: scatterObjects)
        nextObjectID += scatterObjects.count

        loadedObjects.append(
            CullingObject(
                id: nextObjectID,
                bounds: planeLocalBounds.transformed(by: planeModelMatrix),
                drawCalls: [planeDrawCall],
                label: "Tessellated Plane"
            )
        )
        nextObjectID += 1

        if settings.collisionTestSurfaceEnabled,
           let testSurface = Self.makeCollisionTestSurface(
                baseDrawCall: GeometryPrimitives.makeColoredCubeDrawCall(
                    device: device,
                    color: simd_float4(0.12, 0.62, 0.95, 1.0)
                ),
                id: nextObjectID,
                settings: settings
           ) {
            loadedObjects.append(testSurface)
        }

        self.objects = loadedObjects
        self.sceneBounds = Self.computeSceneBounds(objects: loadedObjects)
        self.octree = Octree(objects: loadedObjects)
        let drawCallCount = loadedObjects.reduce(0) { $0 + $1.drawCalls.count }
        print("[Renderer] Deferred scene ready: \(loadedObjects.count) culling objects, \(drawCallCount) draw calls")
    }

    func makeFrameData(viewMatrix: simd_float4x4,
                       projectionMatrix: simd_float4x4,
                       cullingOptions: CullingOptions) -> SceneFrameData {
        SceneCullingEvaluator.makeFrameData(
            objects: objects,
            octree: octree,
            sceneBounds: sceneBounds,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            options: cullingOptions
        )
    }

    func encodeParticles(commandBuffer: MTLCommandBuffer,
                         drawableTexture: MTLTexture,
                         depthTexture: MTLTexture,
                         viewMatrix: simd_float4x4,
                         projectionMatrix: simd_float4x4,
                         time: Float,
                         deltaTime: Float,
                         throttle: Float,
                         renderViewport: RenderViewport?) {
        let transform = settings.engineParticles
        particleEffect.encode(
            commandBuffer: commandBuffer,
            drawableTexture: drawableTexture,
            depthTexture: depthTexture,
            emitterPosition: transform.position,
            exhaustDirection: transform.direction,
            collisionPlane: settings.collisionTestSurfaceEnabled ? Self.makeCollisionPlane(settings: settings) : nil,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            time: time,
            deltaTime: deltaTime,
            throttle: throttle,
            renderViewport: renderViewport
        )
    }

    private static func makeCollisionPlane(settings: Settings) -> RocketEngineCollisionPlane {
        var rotation = matrix_identity_float4x4
        rotateMatrix(matrix: &rotation, rotation: settings.collisionTestSurfaceRotation)
        let normal4 = rotation * simd_float4(1.0, 0.0, 0.0, 0.0)
        let tangent4 = rotation * simd_float4(0.0, 1.0, 0.0, 0.0)
        let bitangent4 = rotation * simd_float4(0.0, 0.0, 1.0, 0.0)
        return RocketEngineCollisionPlane(
            center: settings.collisionTestSurfacePosition,
            normal: simd_normalize(simd_float3(normal4.x, normal4.y, normal4.z)),
            tangent: simd_normalize(simd_float3(tangent4.x, tangent4.y, tangent4.z)),
            bitangent: simd_normalize(simd_float3(bitangent4.x, bitangent4.y, bitangent4.z)),
            halfExtents: simd_float2(
                settings.collisionTestSurfaceScale.y * 0.62,
                settings.collisionTestSurfaceScale.z * 0.62
            )
        )
    }

    private static func makeCollisionTestSurface(baseDrawCall: GeometryDrawCall,
                                                 id: Int,
                                                 settings: Settings) -> CullingObject? {
        guard case var .indexed(indexedDrawCall) = baseDrawCall else { return nil }

        var model = matrix_identity_float4x4
        translateMatrix(matrix: &model, position: settings.collisionTestSurfacePosition)
        rotateMatrix(matrix: &model, rotation: settings.collisionTestSurfaceRotation)
        scaleMatrix(matrix: &model, scale: settings.collisionTestSurfaceScale)

        indexedDrawCall.modelMatrix = model
        indexedDrawCall.material = MaterialDrawState(
            albedoTexture: indexedDrawCall.material.albedoTexture,
            normalTexture: nil,
            displacementTexture: nil,
            specularStrength: 0.10,
            roughness: 0.88,
            opacity: 1.0
        )

        let localBounds = AABB(min: simd_float3(repeating: -0.5), max: simd_float3(repeating: 0.5))
        return CullingObject(
            id: id,
            bounds: localBounds.transformed(by: model),
            drawCalls: [.indexed(indexedDrawCall)],
            label: "Particle Collision Test Surface"
        )
    }

    private static func makeScatterObjects(baseDrawCall: GeometryDrawCall,
                                           startID: Int,
                                           count: Int) -> [CullingObject] {
        guard count > 0, case var .indexed(baseIndexedDrawCall) = baseDrawCall else { return [] }

        let columns = 50
        let spacing: Float = 90.0
        let unitCubeBounds = AABB(min: simd_float3(repeating: -0.5), max: simd_float3(repeating: 0.5))
        var objects: [CullingObject] = []
        objects.reserveCapacity(count)

        for index in 0 ..< count {
            let column = index % columns
            let row = index / columns
            let jitterX = (hash01(index * 17 + 3) - 0.5) * spacing * 0.55
            let jitterZ = (hash01(index * 29 + 11) - 0.5) * spacing * 0.55
            var x = (Float(column) - Float(columns) * 0.5) * spacing + jitterX
            var z = (Float(row) - Float(max(count / columns, 1)) * 0.5) * spacing + jitterZ

            if abs(x) < 420.0 && abs(z) < 420.0 {
                z += z >= 0 ? 520.0 : -520.0
                x += x >= 0 ? 120.0 : -120.0
            }

            let scale = simd_float3(
                18.0 + hash01(index * 5 + 1) * 34.0,
                14.0 + hash01(index * 7 + 9) * 70.0,
                18.0 + hash01(index * 13 + 5) * 34.0
            )

            var model = matrix_identity_float4x4
            translateMatrix(matrix: &model, position: simd_float3(x, scale.y * 0.5, z))
            rotateMatrix(matrix: &model, rotation: simd_float3(0.0, hash01(index * 19 + 21) * .pi, 0.0))
            scaleMatrix(matrix: &model, scale: scale)

            baseIndexedDrawCall.modelMatrix = model
            baseIndexedDrawCall.material = MaterialDrawState(
                albedoTexture: baseIndexedDrawCall.material.albedoTexture,
                normalTexture: nil,
                displacementTexture: nil,
                specularStrength: 0.08,
                roughness: 0.82,
                opacity: 1.0
            )

            objects.append(
                CullingObject(
                    id: startID + index,
                    bounds: unitCubeBounds.transformed(by: model),
                    drawCalls: [.indexed(baseIndexedDrawCall)],
                    label: "Scatter \(index)"
                )
            )
        }

        return objects
    }

    private static func computeSceneBounds(objects: [CullingObject]) -> AABB {
        objects.reduce(AABB.empty) { partial, object in
            partial.union(object.bounds)
        }
    }

    private static func hash01(_ value: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: value)
        x = x &* 747_796_405 &+ 2_891_336_453
        x = ((x >> ((x >> 28) + 4)) ^ x) &* 277_803_737
        x = (x >> 22) ^ x
        return Float(x) / Float(UInt32.max)
    }
}
