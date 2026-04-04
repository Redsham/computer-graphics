import Metal
import MetalKit

// Deferred render targets used as intermediate scene data.
final class GBuffer {
    struct Layout {
        let albedoIndex: Int = 0
        let normalIndex: Int = 1
        // Position is intentionally not stored in GBuffer.
        // It is reconstructed from depth in the lighting pass.
    }

    let layout = Layout()

    private let device: MTLDevice
    private(set) var width: Int = 0
    private(set) var height: Int = 0

    private(set) var albedo: MTLTexture!
    private(set) var normal: MTLTexture!
    private(set) var material: MTLTexture!
    private(set) var depth: MTLTexture!

    init(device: MTLDevice, size: CGSize) {
        self.device = device
        resize(to: size)
    }

    func resize(to size: CGSize) {
        // Recreate textures only when size changes.
        let w = max(Int(size.width), 1)
        let h = max(Int(size.height), 1)
        guard w != width || h != height || albedo == nil else { return }
        width = w
        height = h

        // MRT #0: albedo.rgb.
        let albedoDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        albedoDesc.usage = [.renderTarget, .shaderRead]
        albedoDesc.storageMode = .private
        albedo = device.makeTexture(descriptor: albedoDesc)
        albedo.label = "GBuffer Albedo"

        // MRT #1: world normal + roughness.
        let normalDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        normalDesc.usage = [.renderTarget, .shaderRead]
        normalDesc.storageMode = .private
        normal = device.makeTexture(descriptor: normalDesc)
        normal.label = "GBuffer Normal"

        // MRT #2: specular + opacity.
        let materialDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        materialDesc.usage = [.renderTarget, .shaderRead]
        materialDesc.storageMode = .private
        material = device.makeTexture(descriptor: materialDesc)
        material.label = "GBuffer Material"

        // Shared depth used by geometry write and lighting reconstruction.
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        depthDesc.usage = [.renderTarget, .shaderRead]
        depthDesc.storageMode = .private
        depth = device.makeTexture(descriptor: depthDesc)
        depth.label = "GBuffer Depth"
    }

    func makeGeometryPassDescriptor(clearColor: MTLClearColor) -> MTLRenderPassDescriptor {
        // Render pass that populates all deferred buffers in one geometry pass.
        let rp = MTLRenderPassDescriptor()
        let c0 = rp.colorAttachments[layout.albedoIndex]!
        c0.texture = albedo
        c0.loadAction = .clear
        c0.storeAction = .store
        c0.clearColor = clearColor

        let c1 = rp.colorAttachments[layout.normalIndex]!
        c1.texture = normal
        c1.loadAction = .clear
        c1.storeAction = .store
        c1.clearColor = MTLClearColorMake(0, 0, 0, 0)

        let c2 = rp.colorAttachments[2]!
        c2.texture = material
        c2.loadAction = .clear
        c2.storeAction = .store
        c2.clearColor = MTLClearColorMake(0, 0, 0, 1)

        rp.depthAttachment.texture = depth
        rp.depthAttachment.loadAction = .clear
        rp.depthAttachment.storeAction = .store
        rp.depthAttachment.clearDepth = 1.0
        return rp
    }
}
