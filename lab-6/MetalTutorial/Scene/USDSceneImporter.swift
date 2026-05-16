import Foundation
import Metal
import MetalKit
import ModelIO
import simd

struct SceneGeometry {
    let objects: [CullingObject]
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

    func makeFrameData(viewMatrix: simd_float4x4,
                       projectionMatrix: simd_float4x4,
                       cullingOptions: CullingOptions) -> SceneFrameData
}

final class USDSceneImporter {
    private static let sponzaSpecularStrength: Float = 0.0

    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    func loadSponzaScene(vertexDescriptor: MTLVertexDescriptor) -> SceneGeometry? {
        guard let sceneURL = findSponzaURL() else {
            print("[USDSceneImporter] Sponza asset not found in bundle. Supported names: Sponza_Scene.usdz/.usd/.usdc/.obj")
            return nil
        }

        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        (mdlVertexDescriptor.attributes[0] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
        (mdlVertexDescriptor.attributes[1] as? MDLVertexAttribute)?.name = MDLVertexAttributeTextureCoordinate
        (mdlVertexDescriptor.attributes[2] as? MDLVertexAttribute)?.name = MDLVertexAttributeNormal

        let asset = MDLAsset(url: sceneURL, vertexDescriptor: mdlVertexDescriptor, bufferAllocator: allocator)

        let textureLoadingOptions: [MTKTextureLoader.Option: Any] = [.SRGB: true]
        var objects: [CullingObject] = []
        asset.loadTextures()

        let mdlMeshes = (asset.childObjects(of: MDLMesh.self) as? [MDLMesh]) ?? []
        for mdlMesh in mdlMeshes {
            mdlMesh.vertexDescriptor = mdlVertexDescriptor

            if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.7)
            }

            guard let mtkMesh = try? MTKMesh(mesh: mdlMesh, device: device) else { continue }

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
                        modelMatrix: matrix_identity_float4x4,
                        material: MaterialDrawState(
                            albedoTexture: albedo,
                            normalTexture: nil,
                            displacementTexture: nil,
                            specularStrength: Self.sponzaSpecularStrength,
                            roughness: 0.65,
                            opacity: 1.0
                        )
                    ))
                )
            }

            guard !meshDrawCalls.isEmpty else { continue }

            let boundingBox = mdlMesh.boundingBox
            let bounds = AABB(min: boundingBox.minBounds, max: boundingBox.maxBounds)
            objects.append(
                CullingObject(
                    id: objects.count,
                    bounds: bounds,
                    drawCalls: meshDrawCalls,
                    label: mdlMesh.name.isEmpty ? "Sponza mesh \(objects.count)" : mdlMesh.name
                )
            )
        }

        guard !objects.isEmpty else {
            print("[USDSceneImporter] Sponza asset found but no renderable geometry created")
            return nil
        }

        return SceneGeometry(objects: objects)
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

    private func findSponzaURL() -> URL? {
        let candidates: [(String, String)] = [
            ("Sponza_Scene", "usdz"),
            ("Sponza_Scene", "usd"),
            ("Sponza_Scene", "usdc"),
            ("Sponza_Scene", "obj")
        ]

        for (name, ext) in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        return nil
    }
}
