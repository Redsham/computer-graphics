import Foundation
import Metal
import MetalKit
import simd

final class LODScene: RenderScene {
    struct Settings {
        var modelResourceName: String = "Suzanne"
        var billboardTextureResourceName: String = "Billboard_Suzanne"
        var generatedModelLODLevelCount: Int = 2
        var lodSwitchDistances: [Float] = [650.0, 1400.0]
        var regenerateImportedNormals: Bool = true
        var importedNormalCreaseThreshold: Float = 0.0
        var modelPosition: simd_float3 = simd_float3(repeating: 0.0)
        var modelScale: Float = 1.0
    }

    private enum RuntimeLODContent {
        case model(objects: [CullingObject], octree: Octree)
        case billboard(BillboardTemplate)
    }

    private struct RuntimeLODLevel {
        let sourceIndex: Int
        let name: String
        let content: RuntimeLODContent
        let bounds: AABB
        let drawCallCount: Int
    }

    private struct BillboardTemplate {
        let drawCall: GeometryDrawCall
        let center: simd_float3
        let width: Float
        let height: Float
        let bounds: AABB
    }

    let ambientLight: MtlAmbientLight
    let directionalLight: MtlDirectionalLight
    let pointLights: [MtlPointLight]
    let spotLights: [MtlSpotLight]
    let geometryRendererKind: GeometryRendererKind = .deferredIndexed
    let prefersOrbitingCamera: Bool = false
    let preferredCameraPosition: simd_float3
    let preferredCameraYaw: Float
    let preferredCameraPitch: Float
    let sceneBounds: AABB
    let settings: Settings

    private let levels: [RuntimeLODLevel]
    private let lodSwitchDistances: [Float]
    private var activeLevelIndex: Int = 0
    private var activeDistance: Float = 0.0
    private var lastLoggedLevelIndex: Int?

    var hudStatus: String? {
        guard !levels.isEmpty else { return nil }
        let level = levels[activeLevelIndex]
        let distanceText = String(format: "%.0f", activeDistance)
        return """
        Scene : USD LOD
        LOD   : \(level.name)  Draws: \(level.drawCallCount)
        Dist  : \(distanceText)
        """
    }

    init(device: MTLDevice,
         geometryVertexDescriptor: MTLVertexDescriptor,
         settings: Settings = Settings()) {
        self.settings = settings

        let importer = USDSceneImporter(device: device)
        let modelTransform = Self.makeModelTransform(settings: settings)
        let lodModel = importer.loadLODModel(
            resourceName: settings.modelResourceName,
            vertexDescriptor: geometryVertexDescriptor,
            generatedLevelCount: settings.generatedModelLODLevelCount,
            regenerateNormals: settings.regenerateImportedNormals,
            normalCreaseThreshold: settings.importedNormalCreaseThreshold
        )

        let runtimeLevels: [RuntimeLODLevel]
        if let lodModel {
            runtimeLevels = Self.makeRuntimeLevels(
                from: lodModel.levels,
                device: device,
                modelTransform: modelTransform,
                billboardTextureResourceName: settings.billboardTextureResourceName
            )
            print("[LODScene] Loaded model LOD0/LOD1 and billboard LOD2 from \(settings.modelResourceName)")
        } else {
            runtimeLevels = Self.makeFallbackLevels(
                device: device,
                modelTransform: modelTransform,
                billboardTextureResourceName: settings.billboardTextureResourceName
            )
            print("[LODScene] Loaded fallback cube LOD levels")
        }

        self.levels = runtimeLevels
        self.sceneBounds = runtimeLevels.reduce(AABB.empty) { partial, level in
            partial.union(level.bounds)
        }
        self.lodSwitchDistances = Self.normalizedDistances(
            settings.lodSwitchDistances,
            levelCount: runtimeLevels.count
        )

        self.ambientLight = MtlAmbientLight(color: simd_float3(1.0, 0.98, 0.95), intensity: 0.045)
        self.directionalLight = MtlDirectionalLight(
            direction: simd_normalize(simd_float3(-0.25, -1.0, -0.15)),
            color: simd_float3(1.0, 0.98, 0.95),
            intensity: 0.08
        )
        self.pointLights = [
            MtlPointLight(position: simd_float3(-500.0, 300.0, 0.0), color: simd_float3(1.0, 0.55, 0.32), intensity: 2.0, radius: 700.0),
            MtlPointLight(position: simd_float3(0.0, 300.0, -400.0), color: simd_float3(0.35, 0.55, 1.0), intensity: 2.0, radius: 800.0),
            MtlPointLight(position: simd_float3(500.0, 300.0, 150.0), color: simd_float3(1.0, 0.8, 0.45), intensity: 2.0, radius: 700.0)
        ]
        self.spotLights = []

        self.preferredCameraPosition = simd_float3(0.0, 90.0, 520.0)
        self.preferredCameraYaw = -.pi / 2.0
        self.preferredCameraPitch = -0.05

        let distances = lodSwitchDistances.map { String(format: "%.0f", $0) }.joined(separator: ", ")
        print("[LODScene] Switch distances: [\(distances)]")
    }

    func makeFrameData(viewMatrix: simd_float4x4,
                       projectionMatrix: simd_float4x4,
                       cullingOptions: CullingOptions) -> SceneFrameData {
        let inverseView = viewMatrix.inverse
        let cameraColumn = inverseView.columns.3
        let cameraPosition = simd_float3(cameraColumn.x, cameraColumn.y, cameraColumn.z)
        activeDistance = simd_distance(cameraPosition, sceneBounds.center)
        activeLevelIndex = Self.selectLevelIndex(
            distance: activeDistance,
            switchDistances: lodSwitchDistances,
            levelCount: levels.count
        )

        let level = levels[activeLevelIndex]
        if lastLoggedLevelIndex != level.sourceIndex {
            print("[LODScene] Active \(level.name), distance \(String(format: "%.1f", activeDistance))")
            lastLoggedLevelIndex = level.sourceIndex
        }

        switch level.content {
        case let .model(objects, octree):
            return SceneCullingEvaluator.makeFrameData(
                objects: objects,
                octree: octree,
                sceneBounds: sceneBounds,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                options: cullingOptions
            )
        case let .billboard(template):
            let object = Self.makeBillboardObject(template: template, cameraPosition: cameraPosition)
            return SceneCullingEvaluator.makeFrameData(
                objects: [object],
                octree: Octree(objects: [object]),
                sceneBounds: sceneBounds,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                options: cullingOptions
            )
        }
    }

    private static func makeRuntimeLevels(from levels: [LODGeometryLevel],
                                          device: MTLDevice,
                                          modelTransform: simd_float4x4,
                                          billboardTextureResourceName: String) -> [RuntimeLODLevel] {
        let modelLevels = levels.prefix(2).map { level in
            let objects = level.objects.map { object in
                CullingObject(
                    id: object.id,
                    bounds: object.bounds.transformed(by: modelTransform),
                    drawCalls: object.drawCalls.map { transformedDrawCall($0, by: modelTransform) },
                    label: object.label
                )
            }
            let bounds = objects.reduce(AABB.empty) { partial, object in
                partial.union(object.bounds)
            }
            let drawCallCount = objects.reduce(0) { $0 + $1.drawCalls.count }
            return RuntimeLODLevel(
                sourceIndex: level.index,
                name: level.name,
                content: .model(objects: objects, octree: Octree(objects: objects)),
                bounds: bounds,
                drawCallCount: drawCallCount
            )
        }
        guard let billboardLevel = makeBillboardLevel(
            device: device,
            modelBounds: modelLevels.first?.bounds ?? AABB.empty,
            billboardTextureResourceName: billboardTextureResourceName
        ) else {
            return modelLevels
        }
        return modelLevels + [billboardLevel]
    }

    private static func makeFallbackLevels(device: MTLDevice,
                                           modelTransform: simd_float4x4,
                                           billboardTextureResourceName: String) -> [RuntimeLODLevel] {
        let baseDrawCall = transformedDrawCall(GeometryPrimitives.makeCubeDrawCall(device: device), by: modelTransform)
        let bounds = AABB(min: simd_float3(repeating: -0.5), max: simd_float3(repeating: 0.5)).transformed(by: modelTransform)
        let modelLevels = (0 ..< 2).map { index in
            let object = CullingObject(
                id: 0,
                bounds: bounds,
                drawCalls: [baseDrawCall],
                label: "Fallback LOD\(index)"
            )
            return RuntimeLODLevel(
                sourceIndex: index,
                name: "LOD\(index)",
                content: .model(objects: [object], octree: Octree(objects: [object])),
                bounds: bounds,
                drawCallCount: 1
            )
        }
        guard let billboardLevel = makeBillboardLevel(
            device: device,
            modelBounds: bounds,
            billboardTextureResourceName: billboardTextureResourceName
        ) else {
            return modelLevels
        }
        return modelLevels + [billboardLevel]
    }

    private static func makeBillboardLevel(device: MTLDevice,
                                           modelBounds: AABB,
                                           billboardTextureResourceName: String) -> RuntimeLODLevel? {
        guard modelBounds.isValid else { return nil }
        let template = makeBillboardTemplate(
            device: device,
            modelBounds: modelBounds,
            billboardTextureResourceName: billboardTextureResourceName
        )
        return RuntimeLODLevel(
            sourceIndex: 2,
            name: "LOD2 Billboard",
            content: .billboard(template),
            bounds: template.bounds,
            drawCallCount: 1
        )
    }

    private static func makeBillboardTemplate(device: MTLDevice,
                                              modelBounds: AABB,
                                              billboardTextureResourceName: String) -> BillboardTemplate {
        let extent = modelBounds.extent
        let width = max(max(extent.x, extent.z), 1.0)
        let height = max(extent.y, width * 0.35, 1.0)
        let radius = sqrt((width * 0.5) * (width * 0.5) + (height * 0.5) * (height * 0.5))
        let center = modelBounds.center
        let bounds = AABB(
            min: center - simd_float3(repeating: radius),
            max: center + simd_float3(repeating: radius)
        )
        return BillboardTemplate(
            drawCall: makeBillboardDrawCall(
                device: device,
                billboardTextureResourceName: billboardTextureResourceName
            ),
            center: center,
            width: width,
            height: height,
            bounds: bounds
        )
    }

    private static func makeBillboardObject(template: BillboardTemplate,
                                            cameraPosition: simd_float3) -> CullingObject {
        CullingObject(
            id: 0,
            bounds: template.bounds,
            drawCalls: [makeCameraFacingDrawCall(template: template, cameraPosition: cameraPosition)],
            label: "LOD2 Billboard"
        )
    }

    private static func makeCameraFacingDrawCall(template: BillboardTemplate,
                                                 cameraPosition: simd_float3) -> GeometryDrawCall {
        var toCamera = cameraPosition - template.center
        toCamera.y = 0.0
        if simd_dot(toCamera, toCamera) < 0.0001 {
            toCamera = simd_float3(0.0, 0.0, 1.0)
        }

        let forward = simd_normalize(toCamera)
        let up = simd_float3(0.0, 1.0, 0.0)
        let right = simd_normalize(simd_cross(up, forward))
        var model = matrix_identity_float4x4
        model.columns.0 = simd_float4(right * template.width, 0.0)
        model.columns.1 = simd_float4(up * template.height, 0.0)
        model.columns.2 = simd_float4(forward, 0.0)
        model.columns.3 = simd_float4(template.center, 1.0)

        switch template.drawCall {
        case var .indexed(indexedDrawCall):
            indexedDrawCall.modelMatrix = model
            return .indexed(indexedDrawCall)
        case .tessellated:
            return template.drawCall
        }
    }

    private static func makeBillboardDrawCall(device: MTLDevice,
                                              billboardTextureResourceName: String) -> GeometryDrawCall {
        let vertices: [Vertex] = [
            Vertex(position: simd_float3(-0.5, -0.5, 0.0), normal: simd_float3(0.0, 0.0, 1.0), uv: simd_float2(0.0, 1.0)),
            Vertex(position: simd_float3(0.5, -0.5, 0.0), normal: simd_float3(0.0, 0.0, 1.0), uv: simd_float2(1.0, 1.0)),
            Vertex(position: simd_float3(0.5, 0.5, 0.0), normal: simd_float3(0.0, 0.0, 1.0), uv: simd_float2(1.0, 0.0)),
            Vertex(position: simd_float3(-0.5, 0.5, 0.0), normal: simd_float3(0.0, 0.0, 1.0), uv: simd_float2(0.0, 0.0))
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )!
        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        )!

        return .indexed(IndexedGeometryDrawCall(
            vertexBuffer: vertexBuffer,
            vertexBufferOffset: 0,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            indexCount: indices.count,
            indexType: .uint16,
            primitiveType: .triangle,
            cullMode: .none,
            modelMatrix: matrix_identity_float4x4,
            material: MaterialDrawState(
                albedoTexture: loadBillboardTexture(
                    device: device,
                    resourceName: billboardTextureResourceName
                ) ?? makeFallbackBillboardTexture(device: device),
                normalTexture: nil,
                displacementTexture: nil,
                specularStrength: 0.0,
                roughness: 0.92,
                opacity: 1.0
            )
        ))
    }

    private static func loadBillboardTexture(device: MTLDevice,
                                             resourceName: String) -> MTLTexture? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png") else {
            print("[LODScene] Billboard texture \(resourceName).png not found in bundle")
            return nil
        }

        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(
            URL: url,
            options: [
                MTKTextureLoader.Option.SRGB: true,
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.topLeft
            ]
        )
    }

    private static func makeFallbackBillboardTexture(device: MTLDevice) -> MTLTexture? {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let u = Float(x) / Float(size - 1)
                let v = Float(y) / Float(size - 1)
                let centerFade = max(0.0, 1.0 - abs(u - 0.5) * 1.6) * max(0.0, 1.0 - abs(v - 0.5) * 1.4)
                let shade = UInt8(70.0 + centerFade * 155.0)
                let warm = UInt8(48.0 + centerFade * 80.0)
                let index = (y * size + x) * 4
                pixels[index + 0] = shade
                pixels[index + 1] = UInt8(60.0 + centerFade * 130.0)
                pixels[index + 2] = warm
                pixels[index + 3] = 255
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size * 4
        )
        return texture
    }

    private static func transformedDrawCall(_ drawCall: GeometryDrawCall,
                                            by transform: simd_float4x4) -> GeometryDrawCall {
        switch drawCall {
        case var .indexed(indexedDrawCall):
            indexedDrawCall.modelMatrix = transform * indexedDrawCall.modelMatrix
            return .indexed(indexedDrawCall)
        case var .tessellated(tessellatedDrawCall):
            tessellatedDrawCall.modelMatrix = transform * tessellatedDrawCall.modelMatrix
            return .tessellated(tessellatedDrawCall)
        }
    }

    private static func makeModelTransform(settings: Settings) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        translateMatrix(matrix: &transform, position: settings.modelPosition)
        scaleMatrix(matrix: &transform, scale: simd_float3(repeating: settings.modelScale))
        return transform
    }

    private static func normalizedDistances(_ distances: [Float],
                                            levelCount: Int) -> [Float] {
        guard levelCount > 1 else { return [] }
        var result = distances
            .filter { $0.isFinite && $0 > 0.0 }
            .sorted()
        while result.count < levelCount - 1 {
            let nextDistance = (result.last ?? 500.0) + 500.0
            result.append(nextDistance)
        }
        return Array(result.prefix(levelCount - 1))
    }

    private static func selectLevelIndex(distance: Float,
                                         switchDistances: [Float],
                                         levelCount: Int) -> Int {
        guard levelCount > 1 else { return 0 }
        for (index, switchDistance) in switchDistances.enumerated() {
            if distance < switchDistance {
                return min(index, levelCount - 1)
            }
        }
        return levelCount - 1
    }
}
