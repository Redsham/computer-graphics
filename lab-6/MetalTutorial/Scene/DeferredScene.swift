import Metal
import simd

final class DeferredScene: RenderScene {
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
    let settings: Settings

    private let drawCalls: [GeometryDrawCall]

    init(device: MTLDevice, geometryVertexDescriptor: MTLVertexDescriptor, settings: Settings = Settings()) {
        self.settings = settings
        let importer = USDSceneImporter(device: device)
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

        if let geometry = importer.loadSponzaScene(vertexDescriptor: geometryVertexDescriptor) {
            self.drawCalls = geometry.drawCalls + [planeDrawCall]
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
            print("[Renderer] Loaded Deferred scene: Sponza + Tessellated Plane (\(self.drawCalls.count) draw calls)")
            return
        }

        self.drawCalls = [GeometryPrimitives.makeCubeDrawCall(device: device), planeDrawCall]
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

    func makeDrawCalls(cameraPosition: simd_float3) -> [GeometryDrawCall] {
        drawCalls
    }
}
