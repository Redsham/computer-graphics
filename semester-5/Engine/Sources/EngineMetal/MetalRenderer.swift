import EngineCore
import Metal
import QuartzCore
import os

@MainActor public final class MetalRenderer {
  public let metal: MetalContext
  public let resources: ResourceStore
  public var onError: (@MainActor (String) -> Void)?
  private let passes: [any RenderPass]
  private let cache: PipelineCache
  private let frames: [FrameResources]
  private var frameIndex = 0
  private var submission: UInt64 = 0
  private var preparedConfiguration: EngineConfiguration?
  private var contracts: [TextureContract] = []
  private let logger = Logger(subsystem: "GraphicsEngine", category: "Metal")
  public init(passes: [any RenderPass] = [ForwardPass(), OutputPass()]) throws {
    let metal = try MetalContext()
    self.metal = metal
    resources = ResourceStore(device: metal.device)
    cache = PipelineCache(context: metal)
    self.passes = passes
    frames = try (0..<3).map { try FrameResources(device: metal.device, index: $0) }
    try prepare(configuration: EngineConfiguration())
  }
  private func prepare(configuration: EngineConfiguration) throws {
    guard preparedConfiguration != configuration else { return }
    guard metal.device.supportsTextureSampleCount(configuration.sampleCount) else {
      throw EngineError.invalidConfiguration("GPU does not support selected MSAA.")
    }
    let declarations = passes.map { $0.declaration(configuration: configuration) }
    let nextContracts = try PipelineValidation.validate(declarations)
    let context = PassPreparationContext(metal: metal, configuration: configuration, cache: cache)
    for pass in passes { try pass.prepare(context) }
    contracts = nextContracts
    preparedConfiguration = configuration
  }
  private func targets(frame: FrameResources, size: SIMD2<Int>, samples: Int) throws {
    guard frame.size != size || frame.samples != samples || frame.layout != contracts else {
      return
    }
    var targets: [String: any MTLTexture] = [:]
    for contract in contracts where contract.name != "surface" {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: contract.format, width: size.x, height: size.y, mipmapped: false)
      descriptor.sampleCount = contract.samples
      descriptor.textureType = contract.samples > 1 ? .type2DMultisample : .type2D
      descriptor.storageMode = .private
      descriptor.usage = [.renderTarget, .shaderRead]
      guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
        throw EngineError.unavailable("Could not allocate \(contract.name).")
      }
      texture.label = contract.name
      targets[contract.name] = texture
    }
    frame.targets = targets
    frame.size = size
    frame.samples = samples
    frame.layout = contracts
  }
  /// A nil surface (minimized or unavailable drawable) never acquires a frame slot.
  public func render(
    snapshot: RenderSnapshot, configuration: EngineConfiguration, surface: (any MTLTexture)?,
    drawable: (any CAMetalDrawable)? = nil
  ) throws {
    guard let surface, surface.width > 0, surface.height > 0 else { return }
    guard surface.pixelFormat == .bgra8Unorm_srgb, surface.sampleCount == 1 else {
      throw EngineError.invalidPipeline("Unsupported surface format.")
    }
    let config = try configuration.validated()
    try prepare(configuration: config)
    let frame = frames[frameIndex]
    if frame.completionValue > 0
      && !metal.completion.wait(untilSignaledValue: frame.completionValue, timeoutMS: 1000)
    {
      throw EngineError.unavailable("GPU frame completion timed out.")
    }
    // Only this completed slot is mutated; other slots retain their previous resources.
    frame.retained.removeAll(keepingCapacity: true)
    frame.residency.removeAllAllocations()
    try targets(
      frame: frame, size: SIMD2(surface.width, surface.height), samples: config.sampleCount)
    frame.targets["surface"] = surface
    try frame.upload(
      snapshot: snapshot, configuration: config, resources: resources, device: metal.device)
    frame.residency.addAllocation(frame.uniforms)
    frame.residency.addAllocation(frame.objects)
    for texture in frame.targets.values { frame.residency.addAllocation(texture) }
    for object in snapshot.objects {
      let mesh = try resources.mesh(object.mesh)
      frame.residency.addAllocation(mesh.buffer)
      frame.retained.append(mesh.buffer)
    }
    if let drawable { frame.retained.append(drawable) }
    let context = PassContext(
      commands: frame.commands, frame: frame, resources: resources, snapshot: snapshot,
      configuration: config)
    for pass in passes { try pass.prepareFrame(context) }
    frame.residency.commit()
    frame.allocator.reset()
    frame.commands.beginCommandBuffer(allocator: frame.allocator)
    frame.commands.useResidencySet(frame.residency)
    do {
      for pass in passes { try pass.encode(context) }
    } catch {
      frame.commands.endCommandBuffer()
      throw error
    }
    frame.commands.endCommandBuffer()
    let options = MTL4CommitOptions()
    options.addFeedbackHandler { [weak self] feedback in
      if let error = feedback.error {
        let message = "GPU: \(error.localizedDescription)"
        Task { @MainActor [weak self] in self?.report(message) }
      }
    }
    if let drawable { metal.queue.waitForDrawable(drawable) }
    metal.queue.commit([frame.commands], options: options)
    submission += 1
    metal.queue.signalEvent(metal.completion, value: submission)
    if let drawable {
      metal.queue.signalDrawable(drawable)
      drawable.present()
    }
    frame.completionValue = submission
    frameIndex = (frameIndex + 1) % frames.count
  }
  public func waitUntilIdle() throws {
    if submission > 0 && !metal.completion.wait(untilSignaledValue: submission, timeoutMS: 5000) {
      throw EngineError.unavailable("GPU idle wait timed out.")
    }
  }
  private func report(_ message: String) {
    logger.error("\(message, privacy: .public)")
    onError?(message)
  }
}
