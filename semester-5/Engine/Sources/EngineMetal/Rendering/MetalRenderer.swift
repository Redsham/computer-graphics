import EngineCore
import Metal
import QuartzCore

@MainActor public final class MetalRenderer {
    public let metal: MetalContext
    public let resources: ResourceStore
    public let log: EngineLog
    public var onError: (@MainActor (String) -> Void)?
    public var profiles: ProfileHistory {
        instrumentation.profiles
    }
    public var profilingEnabled: Bool {
        get {
            instrumentation.profilingEnabled
        }
        set {
            instrumentation.profilingEnabled = newValue
        }
    }
    public var lastCapture: FrameCapture? {
        instrumentation.lastCapture
    }
    public var captureRequested: Bool {
        instrumentation.captureRequested
    }
    public private(set) var lastSubmittedFrameID: UInt64 = 0

    private let pipeline: RenderPipelinePlan
    private let instrumentation: RendererInstrumentation
    private let frames: [FrameResources]
    private var frameIndex = 0
    private var submission: UInt64 = 0

    public init(
        passes: [any RenderPass] = [ForwardPass(), OutputPass()], log: EngineLog? = nil,
        enableShaderLogging: Bool = false
    ) throws {
        self.log = try log ?? EngineLog()
        let metal = try MetalContext()
        self.metal = metal
        resources = ResourceStore(device: metal.device, log: self.log)
        frames = try (0..<3).map { try FrameResources(device: metal.device, index: $0) }
        let pipeline = RenderPipelinePlan(metal: metal, passes: passes)
        try pipeline.prepare(configuration: EngineConfiguration())
        self.pipeline = pipeline
        instrumentation = RendererInstrumentation(
            metal: metal, frames: frames, passCount: passes.count, log: self.log,
            enableShaderLogging: enableShaderLogging)
        self.log.write(
            category: "Metal",
            "Initialized \(metal.device.name), \(passes.count) passes, three frame slots.")
    }

    // MARK: - Inspection facade

    public func passDescriptions(configuration: EngineConfiguration) -> [String] {
        pipeline.passes.enumerated().map { index, pass in
            let declaration = pass.declaration(configuration: configuration)
            return
                "\(index + 1). \(declaration.name): [\(declaration.inputs.map(\.name).joined(separator: ", "))] → [\(declaration.outputs.map(\.name).joined(separator: ", "))]"
        }
    }

    public func requestCapture() throws {
        try instrumentation.requestCapture()
    }
    public func clearCapture() {
        instrumentation.clearCapture()
    }
    public func requestGPUTrace(url: URL) throws {
        try instrumentation.requestGPUTrace(url: url)
    }
    public func collectCompletedProfiles() {
        instrumentation.collectCompletedProfiles(frames: frames)
    }

    // MARK: - Frame coordination

    /// A nil surface (minimized or unavailable drawable) never acquires a frame slot.
    public func render(
        snapshot: RenderSnapshot, configuration: EngineConfiguration, surface: (any MTLTexture)?,
        drawable: (any CAMetalDrawable)? = nil
    ) throws {
        guard let surface, surface.width > 0, surface.height > 0 else {
            return
        }
        guard surface.pixelFormat == .bgra8Unorm_srgb, surface.sampleCount == 1 else {
            throw EngineError.invalidPipeline("Unsupported surface format.")
        }

        let cpuStart = CACurrentMediaTime()
        let config = try configuration.validated()
        try pipeline.prepare(configuration: config)
        let frame = frames[frameIndex]
        let waitStart = CACurrentMediaTime()

        if frame.completionValue > 0
            && !metal.completion.wait(untilSignaledValue: frame.completionValue, timeoutMS: 1000)
        {
            throw EngineError.unavailable("GPU frame completion timed out.")
        }

        let waitMilliseconds = (CACurrentMediaTime() - waitStart) * 1000
        collectCompletedProfiles()
        let capturing = instrumentation.beginFrame()
        try frame.prepare(
            snapshot: snapshot, configuration: config, surface: surface,
            drawable: drawable, resources: resources, device: metal.device, pipeline: pipeline,
            capturing: capturing)
        let tracing = try instrumentation.beginTrace(frame: frame) { try waitUntilIdle() }
        defer {
            instrumentation.endTrace(tracing)
        }

        let context = PassContext(
            commands: frame.commands, frame: frame, resources: resources,
            snapshot: snapshot, configuration: config)

        for pass in pipeline.passes {
            try pass.prepareFrame(context)
        }

        frame.residency.commit()
        frame.allocator.reset()
        let passTimings = try instrumentation.encode(pipeline: pipeline, context: context)
        submit(
            frame: frame, snapshot: snapshot, drawable: drawable, cpuStart: cpuStart,
            waitMilliseconds: waitMilliseconds, passTimings: passTimings,
            instrumented: capturing || tracing)

        if capturing || tracing {
            try waitUntilIdle()
            instrumentation.finish(
                frame: frame, frameID: submission, samples: config.sampleCount,
                capturing: capturing, tracing: tracing)
        }
    }

    private func submit(
        frame: FrameResources, snapshot: RenderSnapshot, drawable: (any CAMetalDrawable)?,
        cpuStart: Double, waitMilliseconds: Double, passTimings: [TimingSample],
        instrumented: Bool
    ) {
        // Submit work and publish frame statistics.
        let options = MTL4CommitOptions()
        options.addFeedbackHandler { [weak self] feedback in
            if let error = feedback.error {
                let message = "GPU: \(error.localizedDescription)"
                Task { @MainActor [weak self] in self?.report(message) }
            }
        }

        if let drawable {
            metal.queue.waitForDrawable(drawable)
        }

        metal.queue.commit([frame.commands], options: options)
        submission += 1
        lastSubmittedFrameID = submission
        frame.pendingProfile = profilingEnabled ? (submission, pipeline.names) : nil
        profiles.append(
            FrameProfile(
                id: submission, cpuMilliseconds: (CACurrentMediaTime() - cpuStart) * 1000,
                waitMilliseconds: waitMilliseconds, passesCPU: passTimings, drawCount: frame.drawCount,
                objectCount: snapshot.objects.count, resourceBytes: Int(frame.residency.allocatedSize),
                instrumented: instrumented))
        metal.queue.signalEvent(metal.completion, value: submission)

        if let drawable {
            metal.queue.signalDrawable(drawable)
            drawable.present()
        }

        frame.completionValue = submission
        frameIndex = (frameIndex + 1) % frames.count
    }

    // MARK: - Completion and errors

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
