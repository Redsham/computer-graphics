import EngineCore
import GPUShared
import Metal
import QuartzCore

@MainActor public final class MetalRenderer {
  public let metal: MetalContext
  public let resources: ResourceStore
  public var onError: (@MainActor (String) -> Void)?
  public let log: EngineLog
  public let profiles = ProfileHistory()
  public var profilingEnabled = true
  public private(set) var lastCapture: FrameCapture?
  public private(set) var captureRequested = false
  public private(set) var lastSubmittedFrameID: UInt64 = 0
  private var captureRecorder: CaptureRecorder?
  private var traceURL: URL?
  private var shaderLog: (any MTLLogState)?
  private let passes: [any RenderPass]
  private let cache: PipelineCache
  private let frames: [FrameResources]
  private var frameIndex = 0
  private var submission: UInt64 = 0
  private var preparedConfiguration: EngineConfiguration?
  private var contracts: [TextureContract] = []
  public init(
    passes: [any RenderPass] = [ForwardPass(), OutputPass()], log: EngineLog? = nil,
    enableShaderLogging: Bool = false
  )
    throws
  {
    self.log = try log ?? EngineLog()
    let metal = try MetalContext()
    self.metal = metal
    resources = ResourceStore(device: metal.device, log: self.log)
    cache = PipelineCache(context: metal)
    self.passes = passes
    frames = try (0..<3).map { try FrameResources(device: metal.device, index: $0) }
    try prepare(configuration: EngineConfiguration())
    let descriptor = MTL4CounterHeapDescriptor()
    descriptor.type = .timestamp
    descriptor.count = passes.count * 2
    for frame in frames {
      do { frame.counters = try metal.device.makeCounterHeap(descriptor: descriptor) } catch {
        self.log.write(
          .warning, category: "Profiler",
          "GPU pass timestamps unavailable: \(error.localizedDescription)")
      }
    }
    if enableShaderLogging {
      let logDescriptor = MTLLogStateDescriptor()
      logDescriptor.level = .debug
      logDescriptor.bufferSize = 1024 * 1024
      do {
        shaderLog = try metal.device.makeLogState(descriptor: logDescriptor)
        shaderLog?.addLogHandler { [weak journal = self.log] subsystem, category, level, message in
          let severity: LogLevel =
            (level == .error || level == .fault) ? .error : (level == .debug ? .debug : .info)
          let name = "Shader.\(subsystem ?? "Metal").\(category ?? "GPU")"
          Task { @MainActor in journal?.write(severity, category: name, message) }
        }
      } catch {
        self.log.write(
          .warning, category: "Shader", "Shader logging unavailable: \(error.localizedDescription)")
      }
    }
    self.log.write(
      category: "Metal",
      "Initialized \(metal.device.name), \(passes.count) passes, three frame slots.")
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
  public func passDescriptions(configuration: EngineConfiguration) -> [String] {
    passes.enumerated().map { index, pass in
      let declaration = pass.declaration(configuration: configuration)
      return
        "\(index + 1). \(declaration.name): [\(declaration.inputs.map(\.name).joined(separator: ", "))] → [\(declaration.outputs.map(\.name).joined(separator: ", "))]"
    }
  }
  public func requestCapture() throws {
    if captureRecorder == nil { captureRecorder = try CaptureRecorder(metal: metal) }
    captureRequested = true
    log.write(category: "Debugger", "Capture armed for the next rendered frame.")
  }
  public func clearCapture() {
    lastCapture = nil
    captureRecorder?.passes.removeAll()
  }
  public func requestGPUTrace(url: URL) throws {
    guard shaderLog == nil else {
      throw EngineError.unavailable(
        "Native capture requires a fresh process with enableShaderLogging: false (Metal does not support capturing MTLLogState)."
      )
    }
    guard traceURL == nil, !MTLCaptureManager.shared().isCapturing else {
      throw EngineError.unavailable("A GPU trace is already active.")
    }
    guard MTLCaptureManager.shared().supportsDestination(.gpuTraceDocument) else {
      throw EngineError.unavailable(
        "GPU trace capture is unavailable. Enable MetalCaptureEnabled in the app Info.plist or MTL_CAPTURE_ENABLED=1 before launching."
      )
    }
    guard !FileManager.default.fileExists(atPath: url.path) else {
      throw EngineError.unavailable(
        "Choose a new GPU trace path; existing documents are preserved.")
    }
    traceURL = url
    log.write(category: "Debugger", "Xcode GPU trace armed: \(url.path)")
  }
  public func collectCompletedProfiles() {
    for frame in frames {
      guard let pending = frame.pendingProfile,
        frame.completionValue <= metal.completion.signaledValue
      else { continue }
      frame.pendingProfile = nil
      guard let heap = frame.counters,
        let data = try? heap.resolveCounterRange(0..<(pending.names.count * 2))
      else { continue }
      let frequency = Double(metal.device.queryTimestampFrequency())
      guard frequency > 0, data.count >= pending.names.count * 16 else { continue }
      let ticks = data.withUnsafeBytes { raw in
        (0..<(pending.names.count * 2)).map {
          raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self)
        }
      }
      var samples: [TimingSample] = []
      for (index, name) in pending.names.enumerated() {
        let start = ticks[index * 2]
        let end = ticks[index * 2 + 1]
        if start > 0 && end >= start {
          samples.append(TimingSample(name, milliseconds: Double(end - start) / frequency * 1000))
        }
      }
      if let start = ticks.first, let end = ticks.last, start > 0, end >= start {
        profiles.updateGPU(
          frameID: pending.id, total: Double(end - start) / frequency * 1000, passes: samples)
      }
    }
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
    let cpuStart = CACurrentMediaTime()
    let config = try configuration.validated()
    try prepare(configuration: config)
    let frame = frames[frameIndex]
    let waitStart = CACurrentMediaTime()
    if frame.completionValue > 0
      && !metal.completion.wait(untilSignaledValue: frame.completionValue, timeoutMS: 1000)
    {
      throw EngineError.unavailable("GPU frame completion timed out.")
    }
    let waitMilliseconds = (CACurrentMediaTime() - waitStart) * 1000
    collectCompletedProfiles()
    let capturing = captureRequested
    if capturing {
      captureRequested = false
      captureRecorder?.passes.removeAll()
      captureRecorder?.used = 0
      captureRecorder?.notes.removeAll()
    }
    frame.isCapturing = capturing
    frame.debugBuffers.removeAll()
    frame.debugTextures.removeAll()
    frame.drawCount = 0
    // Only this completed slot is mutated; other slots retain their previous resources.
    frame.retained.removeAll(keepingCapacity: true)
    frame.residency.removeAllAllocations()
    try targets(
      frame: frame, size: SIMD2(surface.width, surface.height), samples: config.sampleCount)
    frame.targets["surface"] = surface
    try frame.upload(
      snapshot: snapshot, configuration: config, resources: resources, device: metal.device)
    if capturing {
      frame.inspectBuffer(
        "Frame uniforms", buffer: frame.uniforms, stride: MemoryLayout<GPUFrame>.stride,
        schema:
          "GPUFrame: viewProjection float4x4 @0; lightDirection float4 @64; lightColor float4 @80; parameters float4 @96"
      )
      frame.inspectBuffer(
        "Objects", buffer: frame.objects,
        range: 0..<(snapshot.objects.count * MemoryLayout<GPUObject>.stride),
        stride: MemoryLayout<GPUObject>.stride,
        schema: "GPUObject: model float4x4 @0; normalMatrix float4x4 @64; baseColor float4 @128")
    }
    frame.residency.addAllocation(frame.uniforms)
    frame.residency.addAllocation(frame.objects)
    for texture in frame.targets.values { frame.residency.addAllocation(texture) }
    for object in snapshot.objects {
      let mesh = try resources.mesh(object.mesh)
      frame.residency.addAllocation(mesh.buffer)
      frame.retained.append(mesh.buffer)
      if capturing {
        frame.inspectBuffer(
          "Mesh \(object.mesh.rawValue)", buffer: mesh.buffer,
          stride: MemoryLayout<GPUVertex>.stride,
          schema: "GPUVertex: position float4 @0; normal float4 @16")
      }
    }
    if let drawable { frame.retained.append(drawable) }
    let preparationContext = PassContext(
      commands: frame.commands, frame: frame, resources: resources, snapshot: snapshot,
      configuration: config)
    for pass in passes { try pass.prepareFrame(preparationContext) }
    frame.residency.commit()
    frame.allocator.reset()
    var tracing = false
    if let url = traceURL {
      try waitUntilIdle()
      let descriptor = MTLCaptureDescriptor()
      descriptor.captureObject = metal.device
      descriptor.destination = .gpuTraceDocument
      descriptor.outputURL = url
      do {
        try MTLCaptureManager.shared().startCapture(with: descriptor)
        tracing = true
        guard let commands = metal.device.makeCommandBuffer() else {
          throw EngineError.unavailable("Could not allocate a captured command buffer.")
        }
        frame.commands = commands
      } catch {
        if tracing {
          MTLCaptureManager.shared().stopCapture()
          tracing = false
        }
        traceURL = nil
        throw error
      }
    }
    defer {
      if tracing {
        MTLCaptureManager.shared().stopCapture()
        traceURL = nil
      }
    }
    let context = PassContext(
      commands: frame.commands, frame: frame, resources: resources, snapshot: snapshot,
      configuration: config)
    if let shaderLog {
      let commandOptions = MTL4CommandBufferOptions()
      commandOptions.logState = shaderLog
      frame.commands.beginCommandBuffer(allocator: frame.allocator, options: commandOptions)
    } else {
      frame.commands.beginCommandBuffer(allocator: frame.allocator)
    }
    frame.commands.useResidencySet(frame.residency)
    var passTimings: [TimingSample] = []
    let names = passes.enumerated().map {
      "\($0.offset + 1). \($0.element.declaration(configuration: config).name)"
    }
    do {
      for (index, pass) in passes.enumerated() {
        if profilingEnabled, let counters = frame.counters {
          frame.commands.writeTimestamp(counterHeap: counters, index: index * 2)
        }
        let start = CACurrentMediaTime()
        try pass.encode(context)
        let milliseconds = (CACurrentMediaTime() - start) * 1000
        passTimings.append(TimingSample(names[index], milliseconds: milliseconds))
        if profilingEnabled, let counters = frame.counters {
          frame.commands.writeTimestamp(counterHeap: counters, index: index * 2 + 1)
        }
        if capturing {
          try captureRecorder?.record(
            pass.declaration(configuration: config), cpu: milliseconds, context: context)
        }
      }
      frame.residency.commit()
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
    lastSubmittedFrameID = submission
    frame.pendingProfile = profilingEnabled ? (submission, names) : nil
    profiles.append(
      FrameProfile(
        id: submission, cpuMilliseconds: (CACurrentMediaTime() - cpuStart) * 1000,
        waitMilliseconds: waitMilliseconds, passesCPU: passTimings, drawCount: frame.drawCount,
        objectCount: snapshot.objects.count, resourceBytes: Int(frame.residency.allocatedSize),
        instrumented: capturing || tracing))
    metal.queue.signalEvent(metal.completion, value: submission)
    if let drawable {
      metal.queue.signalDrawable(drawable)
      drawable.present()
    }
    frame.completionValue = submission
    frameIndex = (frameIndex + 1) % frames.count
    if capturing || tracing {
      try waitUntilIdle()
      if capturing, let recorder = captureRecorder {
        lastCapture = recorder.finish(id: submission, size: frame.size, samples: config.sampleCount)
        log.write(
          category: "Debugger",
          "Frame \(submission) captured: \(recorder.passes.count) passes, \(recorder.used / 1024) KiB."
        )
        recorder.passes.removeAll()
        frame.retained.removeAll(keepingCapacity: true)
        frame.residency.removeAllAllocations()
        frame.residency.commit()
      }
      if tracing { log.write(category: "Debugger", "Xcode GPU trace saved.") }
    }
  }
  public func waitUntilIdle() throws {
    if submission > 0 && !metal.completion.wait(untilSignaledValue: submission, timeoutMS: 5000) {
      throw EngineError.unavailable("GPU idle wait timed out.")
    }
    collectCompletedProfiles()
  }
  private func report(_ message: String) {
    log.write(.error, category: "GPU", message)
    onError?(message)
  }
}
