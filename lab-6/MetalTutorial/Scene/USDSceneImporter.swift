import Foundation
import Metal
import MetalKit
import ModelIO
import simd

struct SceneGeometry {
    let objects: [CullingObject]
    let rootTransform: simd_float4x4
}

struct LODGeometryLevel {
    let index: Int
    let name: String
    let objects: [CullingObject]
    let bounds: AABB
}

struct LODModelGeometry {
    let levels: [LODGeometryLevel]
    let bounds: AABB
}

protocol RenderScene {
    var ambientLight: MtlAmbientLight { get }
    var directionalLight: MtlDirectionalLight { get }
    var pointLights: [MtlPointLight] { get }
    var spotLights: [MtlSpotLight] { get }
    var geometryRendererKind: GeometryRendererKind { get }
    var prefersOrbitingCamera: Bool { get }
    var preferredCameraPosition: simd_float3 { get }
    var preferredCameraYaw: Float { get }
    var preferredCameraPitch: Float { get }
    var sceneBounds: AABB { get }
    var hudStatus: String? { get }
    var particleStatus: String? { get }

    func makeFrameData(viewMatrix: simd_float4x4,
                       projectionMatrix: simd_float4x4,
                       cullingOptions: CullingOptions) -> SceneFrameData

    func encodeParticles(commandBuffer: MTLCommandBuffer,
                         drawableTexture: MTLTexture,
                         depthTexture: MTLTexture,
                         viewMatrix: simd_float4x4,
                         projectionMatrix: simd_float4x4,
                         time: Float,
                         deltaTime: Float,
                         throttle: Float,
                         renderViewport: RenderViewport?)
}

extension RenderScene {
    var hudStatus: String? { nil }
    var particleStatus: String? { nil }

    func encodeParticles(commandBuffer: MTLCommandBuffer,
                         drawableTexture: MTLTexture,
                         depthTexture: MTLTexture,
                         viewMatrix: simd_float4x4,
                         projectionMatrix: simd_float4x4,
                         time: Float,
                         deltaTime: Float,
                         throttle: Float,
                         renderViewport: RenderViewport?) {
    }
}

final class USDSceneImporter {
    private static let defaultSpecularStrength: Float = 0.0
    private static let sponzaSceneScale: Float = 300.0

    private struct ImportedMeshObject {
        let name: String
        let bounds: AABB
        let drawCalls: [GeometryDrawCall]
    }

    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    func loadSponzaScene(vertexDescriptor: MTLVertexDescriptor) -> SceneGeometry? {
        guard let sceneURL = findResourceURL(named: "Sponza_Scene", extensions: ["usdz", "usd", "usdc", "obj"]) else {
            print("[USDSceneImporter] Sponza asset not found in bundle. Supported names: Sponza_Scene.usdz/.usd/.usdc/.obj")
            return nil
        }

        let importedScene = loadMeshObjects(
            from: sceneURL,
            vertexDescriptor: vertexDescriptor,
            regenerateNormals: false,
            normalCreaseThreshold: 0.7,
            sceneScale: Self.sponzaSceneScale
        )
        let objects = makeCullingObjects(from: importedScene.objects, startID: 0, labelPrefix: "Sponza")
        guard !objects.isEmpty else {
            print("[USDSceneImporter] Sponza asset found but no renderable geometry created")
            return nil
        }

        return SceneGeometry(objects: objects, rootTransform: importedScene.rootTransform)
    }

    func loadLODModel(resourceName: String,
                      vertexDescriptor: MTLVertexDescriptor,
                      generatedLevelCount: Int = 3,
                      regenerateNormals: Bool = false,
                      normalCreaseThreshold: Float = 0.7) -> LODModelGeometry? {
        guard let sceneURL = findResourceURL(named: resourceName, extensions: ["usdz", "usd", "usdc", "usda", "obj"]) else {
            print("[USDSceneImporter] LOD asset \(resourceName) not found in bundle")
            return nil
        }

        let importedScene = loadMeshObjects(
            from: sceneURL,
            vertexDescriptor: vertexDescriptor,
            regenerateNormals: regenerateNormals,
            normalCreaseThreshold: normalCreaseThreshold
        )
        let importedObjects = importedScene.objects
        guard !importedObjects.isEmpty else {
            print("[USDSceneImporter] LOD asset \(resourceName) found but no renderable geometry created")
            return nil
        }

        // Preferred USD convention: meshes named LOD0_*, LOD1_*, LOD2_* are grouped into explicit levels.
        let explicitLevels = makeExplicitLODLevels(from: importedObjects)
        let levels = explicitLevels.count >= 2
            ? explicitLevels
            : makeDerivedLODLevels(from: importedObjects, levelCount: generatedLevelCount)

        guard levels.count >= 2 else {
            print("[USDSceneImporter] LOD asset \(resourceName) needs at least two LOD levels")
            return nil
        }

        let bounds = levels.reduce(AABB.empty) { partial, level in
            partial.union(level.bounds)
        }
        let levelSummary = levels
            .map { "\($0.name): \($0.objects.count) objects" }
            .joined(separator: ", ")
        print("[USDSceneImporter] Loaded USD LOD model \(resourceName): \(levelSummary)")
        return LODModelGeometry(levels: levels, bounds: bounds)
    }

    private struct ImportedScene {
        let objects: [ImportedMeshObject]
        let rootTransform: simd_float4x4
    }

    private func loadMeshObjects(from sceneURL: URL,
                                 vertexDescriptor: MTLVertexDescriptor,
                                 regenerateNormals: Bool,
                                 normalCreaseThreshold: Float,
                                 sceneScale: Float = 1.0) -> ImportedScene {
        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        (mdlVertexDescriptor.attributes[0] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
        (mdlVertexDescriptor.attributes[1] as? MDLVertexAttribute)?.name = MDLVertexAttributeTextureCoordinate
        (mdlVertexDescriptor.attributes[2] as? MDLVertexAttribute)?.name = MDLVertexAttributeNormal

        let asset = MDLAsset(url: sceneURL, vertexDescriptor: mdlVertexDescriptor, bufferAllocator: allocator)

        let textureLoadingOptions: [MTKTextureLoader.Option: Any] = [.SRGB: true]
        asset.loadTextures()

        var objects: [ImportedMeshObject] = []
        let rootTransform = Self.rootTransform(upAxis: asset.upAxis, sceneScale: sceneScale)
        for index in 0 ..< asset.count {
            appendMeshObjects(
                from: asset.object(at: index),
                parentTransform: rootTransform,
                inheritedLODName: nil,
                vertexDescriptor: mdlVertexDescriptor,
                regenerateNormals: regenerateNormals,
                normalCreaseThreshold: normalCreaseThreshold,
                textureLoadingOptions: textureLoadingOptions,
                objects: &objects
            )
        }

        return ImportedScene(objects: objects, rootTransform: rootTransform)
    }

    private func appendMeshObjects(from object: MDLObject,
                                   parentTransform: simd_float4x4,
                                   inheritedLODName: String?,
                                   vertexDescriptor: MDLVertexDescriptor,
                                   regenerateNormals: Bool,
                                   normalCreaseThreshold: Float,
                                   textureLoadingOptions: [MTKTextureLoader.Option: Any],
                                   objects: inout [ImportedMeshObject]) {
        let localTransform = object.transform?.matrix ?? matrix_identity_float4x4
        let objectTransform = parentTransform * localTransform
        let nextLODName = Self.explicitLODIndex(in: object.name) == nil ? inheritedLODName : object.name

        if let mdlMesh = object as? MDLMesh {
            appendMeshObject(
                mdlMesh,
                transform: objectTransform,
                inheritedLODName: inheritedLODName,
                vertexDescriptor: vertexDescriptor,
                regenerateNormals: regenerateNormals,
                normalCreaseThreshold: normalCreaseThreshold,
                textureLoadingOptions: textureLoadingOptions,
                objects: &objects
            )
        }

        for child in object.children.objects {
            appendMeshObjects(
                from: child,
                parentTransform: objectTransform,
                inheritedLODName: nextLODName,
                vertexDescriptor: vertexDescriptor,
                regenerateNormals: regenerateNormals,
                normalCreaseThreshold: normalCreaseThreshold,
                textureLoadingOptions: textureLoadingOptions,
                objects: &objects
            )
        }
    }

    private func appendMeshObject(_ mdlMesh: MDLMesh,
                                  transform: simd_float4x4,
                                  inheritedLODName: String?,
                                  vertexDescriptor: MDLVertexDescriptor,
                                  regenerateNormals: Bool,
                                  normalCreaseThreshold: Float,
                                  textureLoadingOptions: [MTKTextureLoader.Option: Any],
                                  objects: inout [ImportedMeshObject]) {
        mdlMesh.vertexDescriptor = vertexDescriptor

        if regenerateNormals {
            mdlMesh.removeAttributeNamed(MDLVertexAttributeNormal)
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: normalCreaseThreshold)
            mdlMesh.vertexDescriptor = vertexDescriptor
        } else if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: normalCreaseThreshold)
        }

        guard let mtkMesh = try? MTKMesh(mesh: mdlMesh, device: device) else { return }

        var meshDrawCalls: [GeometryDrawCall] = []
        for (index, mtkSubmesh) in mtkMesh.submeshes.enumerated() {
            let mdlSubmesh = mdlMesh.submeshes?[index] as? MDLSubmesh
            let albedo = mdlSubmesh.flatMap { loadBaseColorTexture(from: $0.material, textureLoadingOptions: textureLoadingOptions) }

            meshDrawCalls.append(
                .indexed(IndexedGeometryDrawCall(
                    vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                    vertexBufferOffset: mtkMesh.vertexBuffers[0].offset,
                    indexBuffer: mtkSubmesh.indexBuffer.buffer,
                    indexBufferOffset: mtkSubmesh.indexBuffer.offset,
                    indexCount: mtkSubmesh.indexCount,
                    indexType: mtkSubmesh.indexType,
                    primitiveType: mtkSubmesh.primitiveType,
                    cullMode: .none,
                    modelMatrix: transform,
                    material: MaterialDrawState(
                        albedoTexture: albedo,
                        normalTexture: nil,
                        displacementTexture: nil,
                        specularStrength: Self.defaultSpecularStrength,
                        roughness: 0.65,
                        opacity: 1.0
                    )
                ))
            )
        }

        guard !meshDrawCalls.isEmpty else { return }

        let boundingBox = mdlMesh.boundingBox
        let bounds = AABB(min: boundingBox.minBounds, max: boundingBox.maxBounds)
            .transformed(by: transform)
        let objectName = Self.objectName(
            meshName: mdlMesh.name,
            inheritedLODName: inheritedLODName,
            fallbackIndex: objects.count
        )
        objects.append(
            ImportedMeshObject(
                name: objectName,
                bounds: bounds,
                drawCalls: meshDrawCalls
            )
        )
    }

    private static func objectName(meshName: String,
                                   inheritedLODName: String?,
                                   fallbackIndex: Int) -> String {
        let baseName = meshName.isEmpty ? "USD mesh \(fallbackIndex)" : meshName
        guard let inheritedLODName,
              explicitLODIndex(in: baseName) == nil else {
            return baseName
        }
        return "\(inheritedLODName)_\(baseName)"
    }

    private static func upAxisTransform(for upAxis: simd_float3) -> simd_float4x4 {
        let absAxis = simd_abs(upAxis)
        guard absAxis.z > absAxis.y else { return matrix_identity_float4x4 }

        var transform = matrix_identity_float4x4
        transform.columns.0 = simd_float4(1.0, 0.0, 0.0, 0.0)
        transform.columns.1 = simd_float4(0.0, 0.0, -1.0, 0.0)
        transform.columns.2 = simd_float4(0.0, 1.0, 0.0, 0.0)
        transform.columns.3 = simd_float4(0.0, 0.0, 0.0, 1.0)
        return transform
    }

    private static func rootTransform(upAxis: simd_float3, sceneScale: Float) -> simd_float4x4 {
        var transform = upAxisTransform(for: upAxis)
        guard sceneScale != 1.0 else { return transform }

        transform.columns.0 *= sceneScale
        transform.columns.1 *= sceneScale
        transform.columns.2 *= sceneScale
        return transform
    }

    private func loadBaseColorTexture(from material: MDLMaterial?, textureLoadingOptions: [MTKTextureLoader.Option: Any]) -> MTLTexture? {
        guard let material else { return nil }
        guard let baseColor = material.property(with: .baseColor) else { return nil }

        if baseColor.type == .texture, let sampler = baseColor.textureSamplerValue, let mdlTexture = sampler.texture {
            return try? textureLoader.newTexture(texture: mdlTexture, options: textureLoadingOptions)
        }

        if baseColor.type == .string, let textureName = baseColor.stringValue {
            return textureFromBundle(named: textureName, textureLoadingOptions: textureLoadingOptions)
        }

        if baseColor.type == MDLMaterialPropertyType.URL, let url = baseColor.urlValue {
            return try? textureLoader.newTexture(URL: url, options: textureLoadingOptions)
        }

        return nil
    }

    private func textureFromBundle(named: String, textureLoadingOptions: [MTKTextureLoader.Option: Any]) -> MTLTexture? {
        let ns = named as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "png" : ns.pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { return nil }
        return try? textureLoader.newTexture(URL: url, options: textureLoadingOptions)
    }

    private func makeExplicitLODLevels(from importedObjects: [ImportedMeshObject]) -> [LODGeometryLevel] {
        var groups: [Int: [ImportedMeshObject]] = [:]
        for object in importedObjects {
            guard let lodIndex = Self.explicitLODIndex(in: object.name) else { continue }
            groups[lodIndex, default: []].append(object)
        }

        return groups.keys.sorted().compactMap { index in
            makeLODLevel(index: index, name: "LOD\(index)", importedObjects: groups[index] ?? [])
        }
    }

    private func makeDerivedLODLevels(from importedObjects: [ImportedMeshObject],
                                      levelCount: Int) -> [LODGeometryLevel] {
        let count = max(2, levelCount)
        let sortedObjects = importedObjects.sorted { lhs, rhs in
            Self.importance(of: lhs.bounds) > Self.importance(of: rhs.bounds)
        }

        var levels: [LODGeometryLevel] = []
        for index in 0 ..< count {
            let keepRatio = pow(0.45, Float(index))
            let objectCount = max(1, Int(ceil(Float(sortedObjects.count) * keepRatio)))
            let selectedObjects = Array(sortedObjects.prefix(objectCount))
            if let level = makeLODLevel(index: index, name: "LOD\(index)", importedObjects: selectedObjects) {
                levels.append(level)
            }
        }

        return levels
    }

    private func makeLODLevel(index: Int,
                              name: String,
                              importedObjects: [ImportedMeshObject]) -> LODGeometryLevel? {
        let objects = makeCullingObjects(from: importedObjects, startID: 0, labelPrefix: name)
        guard !objects.isEmpty else { return nil }
        let bounds = objects.reduce(AABB.empty) { partial, object in
            partial.union(object.bounds)
        }
        return LODGeometryLevel(index: index, name: name, objects: objects, bounds: bounds)
    }

    private func makeCullingObjects(from importedObjects: [ImportedMeshObject],
                                    startID: Int,
                                    labelPrefix: String) -> [CullingObject] {
        importedObjects.enumerated().map { offset, object in
            CullingObject(
                id: startID + offset,
                bounds: object.bounds,
                drawCalls: object.drawCalls,
                label: "\(labelPrefix) \(object.name)"
            )
        }
    }

    private static func explicitLODIndex(in name: String) -> Int? {
        let uppercaseName = name.uppercased()
        guard let range = uppercaseName.range(of: "LOD") else { return nil }

        var digits = ""
        var index = range.upperBound
        while index < uppercaseName.endIndex {
            let character = uppercaseName[index]
            if character.isNumber {
                digits.append(character)
            } else if digits.isEmpty && (character == "_" || character == "-" || character == " ") {
                uppercaseName.formIndex(after: &index)
                continue
            } else {
                break
            }
            uppercaseName.formIndex(after: &index)
        }

        return Int(digits)
    }

    private static func importance(of bounds: AABB) -> Float {
        let extent = simd_max(bounds.extent, simd_float3(repeating: 0.001))
        return extent.x * extent.y * extent.z
    }

    private func findResourceURL(named resourceName: String, extensions: [String]) -> URL? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: ext) {
                return url
            }
        }

        return nil
    }
}
