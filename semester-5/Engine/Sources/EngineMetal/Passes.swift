import EngineCore
import GPUShared
import Metal

@MainActor public final class ForwardPass: RenderPass {
  private var state: (any MTLRenderPipelineState)?
  private var depthState: (any MTLDepthStencilState)?
  public init() {}
  public func declaration(configuration: EngineConfiguration) -> PassDeclaration {
    var outputs = [
      TextureContract("hdr", format: .rgba16Float),
      TextureContract("depth", format: .depth32Float, samples: configuration.sampleCount),
    ]
    if configuration.sampleCount > 1 {
      outputs.append(
        TextureContract("msaaHDR", format: .rgba16Float, samples: configuration.sampleCount))
    }
    return PassDeclaration(name: "Forward", outputs: outputs)
  }
  public func prepare(_ context: PassPreparationContext) throws {
    state = try context.pipeline(
      vertex: "forwardVertex", fragment: "forwardFragment", color: .rgba16Float,
      samples: context.configuration.sampleCount)
    guard depthState == nil else { return }
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    guard let depth = context.metal.device.makeDepthStencilState(descriptor: descriptor) else {
      throw EngineError.unavailable("Could not create depth state.")
    }
    depthState = depth
  }
  public func encode(_ context: PassContext) throws {
    guard let state, let depthState else {
      throw EngineError.invalidPipeline("Forward pass was not prepared.")
    }
    let descriptor = MTL4RenderPassDescriptor()
    let color = descriptor.colorAttachments[0]!
    let hdr = try context.texture("hdr")
    if context.configuration.sampleCount > 1 {
      color.texture = try context.texture("msaaHDR")
      color.resolveTexture = hdr
      color.storeAction =
        context.frame.isCapturing ? .storeAndMultisampleResolve : .multisampleResolve
    } else {
      color.texture = hdr
      color.storeAction = .store
    }
    color.loadAction = .clear
    let background = context.configuration.background
    color.clearColor = MTLClearColorMake(
      Double(background.x), Double(background.y), Double(background.z), 1)
    descriptor.depthAttachment.texture = try context.texture("depth")
    descriptor.depthAttachment.loadAction = .clear
    descriptor.depthAttachment.storeAction = .store
    descriptor.depthAttachment.clearDepth = 1
    guard let encoder = context.commands.makeRenderCommandEncoder(descriptor: descriptor) else {
      throw EngineError.unavailable("Could not create forward encoder.")
    }
    defer { encoder.endEncoding() }
    encoder.label = "ForwardPass"
    context.synchronize(encoder)
    encoder.setRenderPipelineState(state)
    encoder.setDepthStencilState(depthState)
    encoder.setCullMode(.back)
    encoder.setFrontFacing(.counterClockwise)
    encoder.setTriangleFillMode(context.configuration.wireframe ? .lines : .fill)
    context.retain(state)
    context.retain(depthState)
    let table = context.frame.forwardArguments
    table.setAddress(context.frame.uniforms.gpuAddress, index: Int(GPUFrameBinding))
    table.setAddress(context.frame.objects.gpuAddress, index: Int(GPUObjectBinding))
    for (index, object) in context.snapshot.objects.enumerated() {
      let mesh = try context.resources.mesh(object.mesh)
      table.setAddress(mesh.buffer.gpuAddress, index: Int(GPUVertexBinding))
      encoder.setArgumentTable(table, stages: [.vertex, .fragment])
      context.recordDraw()
      encoder.drawPrimitives(
        primitiveType: .triangle, vertexStart: 0, vertexCount: mesh.count, instanceCount: 1,
        baseInstance: index)
    }
  }
}
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
    guard let state else { throw EngineError.invalidPipeline("Output pass was not prepared.") }
    let descriptor = MTL4RenderPassDescriptor()
    descriptor.colorAttachments[0].texture = try context.texture("surface")
    descriptor.colorAttachments[0].loadAction = .dontCare
    descriptor.colorAttachments[0].storeAction = .store
    guard let encoder = context.commands.makeRenderCommandEncoder(descriptor: descriptor) else {
      throw EngineError.unavailable("Could not create output encoder.")
    }
    defer { encoder.endEncoding() }
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
