import Foundation
import Metal
import MetalKit
import ModelIO
import simd

struct SceneGeometry {
    let drawCalls: [GeometryDrawCall]
}

enum SceneLightRig {
    static func sponza() -> (MtlDirectionalLight, [MtlPointLight], [MtlSpotLight]) {
        let directional = MtlDirectionalLight(
            direction: simd_normalize(simd_float3(-0.25, -1.0, -0.15)),
            color: simd_float3(1.0, 0.98, 0.95),
            intensity: 0.55
        )

        let pointLights: [MtlPointLight] = [
            MtlPointLight(position: simd_float3(-500.0, 300.0, 0.0), color: simd_float3(1.0, 0.55, 0.32), intensity: 2.0, radius: 700.0),
            MtlPointLight(position: simd_float3(0.0, 300.0, -400.0), color: simd_float3(0.35, 0.55, 1.0), intensity: 2.0, radius: 800.0),
            MtlPointLight(position: simd_float3(500.0, 300.0, 150.0), color: simd_float3(1.0, 0.8, 0.45), intensity: 2.0, radius: 700.0),
            MtlPointLight(position: simd_float3(0.0, 500.0, 600.0), color: simd_float3(0.5, 1.0, 0.8), intensity: 2.0, radius: 900.0)
        ]

        let spotLights: [MtlSpotLight] = [
            MtlSpotLight(position: simd_float3(-0.0, 300.0, 0.0), direction: simd_normalize(simd_float3(1.0, 0.0, 0.0)), color: simd_float3(1.0, 0.0, 0.0), intensity: 28.0, innerCos: cos(12.0 * .pi / 180.0), outerCos: cos(22.0 * .pi / 180.0), radius: 1800.0)
        ]

        return (directional, pointLights, spotLights)
    }
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

        let textureLoadingOptions: [MTKTextureLoader.Option: Any] = [.SRGB: false]
        var drawCalls: [GeometryDrawCall] = []
        asset.loadTextures()

        let mdlMeshes = (asset.childObjects(of: MDLMesh.self) as? [MDLMesh]) ?? []
        for mdlMesh in mdlMeshes {
            mdlMesh.vertexDescriptor = mdlVertexDescriptor

            if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.7)
            }

            guard let mtkMesh = try? MTKMesh(mesh: mdlMesh, device: device) else { continue }

            for (index, mtkSubmesh) in mtkMesh.submeshes.enumerated() {
                let mdlSubmesh = mdlMesh.submeshes?[index] as? MDLSubmesh
                let albedo = mdlSubmesh.flatMap { loadBaseColorTexture(from: $0.material, textureLoadingOptions: textureLoadingOptions) }

                drawCalls.append(
                    GeometryDrawCall(
                        vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                        vertexBufferOffset: mtkMesh.vertexBuffers[0].offset,
                        indexBuffer: mtkSubmesh.indexBuffer.buffer,
                        indexBufferOffset: mtkSubmesh.indexBuffer.offset,
                        indexCount: mtkSubmesh.indexCount,
                        indexType: mtkSubmesh.indexType,
                        primitiveType: mtkSubmesh.primitiveType,
                        modelMatrix: matrix_identity_float4x4,
                        albedoTexture: albedo,
                        specularStrength: Self.sponzaSpecularStrength
                    )
                )
            }
        }

        guard !drawCalls.isEmpty else {
            print("[USDSceneImporter] Sponza asset found but no renderable geometry created")
            return nil
        }

        return SceneGeometry(drawCalls: drawCalls)
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
