import EngineCore
import GPUShared
import Metal

// MARK: - Tone mapping and output

@MainActor public final class OutputPass: RenderPass {
    private var state: (any MTLRenderPipelineState)?

    public init() {}

    public func declaration(configuration: EngineConfiguration) -> PassDeclaration {
        PassDeclaration(
            name: "Output", inputs: [TextureContract("hdr", format: .rgba16Float)],
            outputs: [TextureContract("surface", format: .bgra8Unorm_srgb)])
    }

    public func prepare(_ context: PassPreparationContext) throws {
        state = try context.pipeline(
            vertex: "outputVertex", fragment: "outputFragment", color: .bgra8Unorm_srgb)
    }

    public func encode(_ context: PassContext) throws {
        guard let state else {
            throw EngineError.invalidPipeline("Output pass was not prepared.")
        }

        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = try context.texture("surface")
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = context.commands.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw EngineError.unavailable("Could not create output encoder.")
        }

        defer {
            encoder.endEncoding()
        }

        encoder.label = "OutputPass"
        context.synchronize(encoder)
        encoder.setRenderPipelineState(state)
        let table = context.frame.outputArguments
        table.setAddress(context.frame.uniforms.gpuAddress, index: Int(GPUFrameBinding))
        table.setTexture(try context.texture("hdr").gpuResourceID, index: Int(GPUColorTexture))
        encoder.setArgumentTable(table, stages: [.vertex, .fragment])
        context.recordDraw()
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        context.retain(state)
    }
}
