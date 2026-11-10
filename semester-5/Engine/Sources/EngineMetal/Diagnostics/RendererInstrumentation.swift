import EngineCore
import Metal
import QuartzCore

/// Profiling, readback, shader logs and native traces are optional renderer services.
@MainActor final class RendererInstrumentation {
    let profiles = ProfileHistory()
    var profilingEnabled = true
    private(set) var lastCapture: FrameCapture?
    private(set) var captureRequested = false
    private var captureRecorder: CaptureRecorder?
    private var traceURL: URL?
    private var shaderLog: (any MTLLogState)?
    private let metal: MetalContext
    private let log: EngineLog

    init(
        metal: MetalContext, frames: [FrameResources], passCount: Int, log: EngineLog,
        enableShaderLogging: Bool
    ) {
        self.metal = metal
        self.log = log
        let descriptor = MTL4CounterHeapDescriptor()
        descriptor.type = .timestamp
        descriptor.count = passCount * 2

        for frame in frames {
            do {
                frame.counters = try metal.device.makeCounterHeap(descriptor: descriptor)
            } catch {
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
    }

    func requestCapture() throws {
        if captureRecorder == nil {
            captureRecorder = try CaptureRecorder(metal: metal)
        }

        captureRequested = true
        log.write(category: "Debugger", "Capture armed for the next rendered frame.")
    }

    func clearCapture() {
        lastCapture = nil
        captureRecorder?.passes.removeAll()
    }

    func requestGPUTrace(url: URL) throws {
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

    func collectCompletedProfiles(frames: [FrameResources]) {
        for frame in frames {
            guard let pending = frame.pendingProfile,
                frame.completionValue <= metal.completion.signaledValue
            else {
                continue
            }

            frame.pendingProfile = nil

            guard let heap = frame.counters,
                let data = try? heap.resolveCounterRange(0..<(pending.names.count * 2))
            else {
                continue
            }

            let frequency = Double(metal.device.queryTimestampFrequency())

            guard frequency > 0, data.count >= pending.names.count * 16 else {
                continue
            }

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

    func beginFrame() -> Bool {
        let capturing = captureRequested
        captureRequested = false

        if capturing {
            captureRecorder?.reset()
        }

        return capturing
    }

    func beginTrace(frame: FrameResources, waitUntilIdle: () throws -> Void) throws -> Bool {
        // Start an optional native GPU capture.
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

        return tracing
    }

    func endTrace(_ tracing: Bool) {
        if tracing {
            MTLCaptureManager.shared().stopCapture()
            traceURL = nil
        }
    }

    func encode(pipeline: RenderPipelinePlan, context: PassContext) throws -> [TimingSample] {
        let frame = context.frame
        let capturing = frame.isCapturing
        let names = pipeline.names
        let declarations = pipeline.declarations
        let passes = pipeline.passes
        if let shaderLog {
            let commandOptions = MTL4CommandBufferOptions()
            commandOptions.logState = shaderLog
            frame.commands.beginCommandBuffer(allocator: frame.allocator, options: commandOptions)
        } else {
            frame.commands.beginCommandBuffer(allocator: frame.allocator)
        }

        frame.commands.useResidencySet(frame.residency)
        var passTimings: [TimingSample] = []
        passTimings.reserveCapacity(passes.count)

        defer {
            frame.commands.endCommandBuffer()
        }

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
                    declarations[index], cpu: milliseconds, context: context)
            }
        }

        frame.residency.commit()

        return passTimings
    }

    /// The caller has already waited for GPU completion before assembling CPU snapshots.
    func finish(frame: FrameResources, frameID: UInt64, samples: Int, capturing: Bool, tracing: Bool) {
        if capturing, let recorder = captureRecorder {
            lastCapture = recorder.finish(id: frameID, size: frame.size, samples: samples)
            log.write(
                category: "Debugger",
                "Frame \(frameID) captured: \(recorder.passes.count) passes, \(recorder.used / 1024) KiB."
            )
            recorder.passes.removeAll()
            frame.retained.removeAll(keepingCapacity: true)
            frame.residency.removeAllAllocations()
            frame.residency.commit()
        }

        if tracing {
            log.write(category: "Debugger", "Xcode GPU trace saved.")
        }
    }
}
