import AppKit
import EngineCore
import EngineMetal
import MetalKit
import QuartzCore
import SwiftUI
import os

@MainActor public final class EngineSession: NSObject, ObservableObject, MTKViewDelegate {
    // MARK: - Engine services

    public let world = World()
    public let renderer: MetalRenderer
    public let log: EngineLog
    public let commands = ConsoleCommands()

    // MARK: - Diagnostics state

    @Published public var diagnosticsVisible = true
    @Published public var diagnosticsTab = "Console"
    @Published public internal(set) var logEntries: [LogEntry] = []
    @Published public internal(set) var profileFrames: [FrameProfile] = []
    @Published public internal(set) var capturedFrame: FrameCapture?
    @Published public internal(set) var simulationPaused = false
    @Published public internal(set) var stepRequested = false

    public var viewportPaused: Bool {
        isRenderingPaused || (simulationPaused && !stepRequested)
    }

    var logRevision: UInt64 = .max
    private var diagnosticsTime: Double = 0

    // MARK: - Settings and frame statistics

    @Published public var configuration: EngineConfiguration
    @Published public private(set) var message: String?
    @Published public private(set) var fps: Double = 0
    @Published public private(set) var cpuMilliseconds: Double = 0
    @Published public private(set) var objectCount: Int = 0
    @Published public private(set) var isRenderingPaused = false

    // MARK: - Frame coordination

    private let store: ConfigurationStore
    private let scheduler: SystemScheduler
    private let frame = FrameContext()
    var clock = FrameClock()
    private var applied: EngineConfiguration
    private var statsStart = CACurrentMediaTime()
    private var statsFrames = 0
    private var statsCPU = 0.0
    private var stopped = false
    private var needsSave = false
    private let logger = Logger(subsystem: "GraphicsEngine", category: "Application")

    // MARK: - Initialization

    public init(
        defaultsData: Data, settingsName: String, systems: [any EngineSystem],
        passes: [any RenderPass] = [ForwardPass(), OutputPass()], enableShaderLogging: Bool = false
    ) throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        store = try ConfigurationStore(
            defaultsData: defaultsData,
            userURL: support.appending(path: settingsName).appending(path: "settings.json"))
        let result = store.load()
        configuration = result.configuration
        applied = result.configuration
        message = result.warning
        let log = try EngineLog(
            fileURL: support.appending(path: settingsName).appending(path: "Logs/engine.jsonl"))
        self.log = log
        renderer = try MetalRenderer(passes: passes, log: log, enableShaderLogging: enableShaderLogging)
        scheduler = SystemScheduler(systems: systems)
        super.init()
        renderer.onError = { [weak self] message in
            self?.isRenderingPaused = true
            self?.report(message)
        }
        configureCommands()

        if let warning = result.warning {
            log.write(.warning, category: "Settings", warning)
        }

        log.write(category: "Application", "Session ready. Type help for commands.")
        refreshDiagnostics()
    }

    // MARK: - Settings

    public func resetSettings() {
        configuration = store.defaults
        needsSave = true
        retry()
    }

    public func clearMessage() {
        message = nil
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        frame.aspectRatio = Float(size.width / max(size.height, 1))
    }

    public func draw(in view: MTKView) {
        // MTKView can deliver an already queued draw after isPaused changes.
        guard !stopped, !isRenderingPaused, !simulationPaused || stepRequested,
            let view = view as? EngineMetalView
        else {
            return
        }

        let start = CACurrentMediaTime()
        frame.deltaTime =
            simulationPaused && stepRequested ? 1 / Float(configuration.targetFPS) : clock.tick(at: start)

        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
            let drawable = view.currentDrawable
        else {
            return
        }

        do {

            // Apply input and update the scene.
            let next = try configuration.validated()
            frame.configuration = next
            frame.aspectRatio = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
            frame.input = view.input.snapshot()
            scheduler.update(world: world, frame: frame)

            // Render the extracted snapshot.
            let capturing = renderer.captureRequested
            try renderer.render(
                snapshot: frame.snapshot, configuration: next, surface: drawable.texture, drawable: drawable
            )
            renderer.profiles.updateCPU(
                frameID: renderer.lastSubmittedFrameID, total: (CACurrentMediaTime() - start) * 1000,
                systems: scheduler.lastTimings)

            // Publish capture and diagnostics state.
            if capturing {
                capturedFrame = renderer.lastCapture
                simulationPaused = true
                diagnosticsTab = "Frame"
                diagnosticsVisible = true
            }

            if stepRequested {
                stepRequested = false
            }

            view.isPaused = viewportPaused

            if start - diagnosticsTime > 0.2 || capturing || simulationPaused {
                diagnosticsTime = start
                refreshDiagnostics()
            }

            // Persist settings at the frame boundary.
            view.preferredFramesPerSecond = next.targetFPS

            if next != applied || needsSave {
                try store.save(next)
                applied = next
                needsSave = false
                log.write(.debug, category: "Settings", "Configuration applied and saved.")
            }

            // Accumulate display statistics.
            statsFrames += 1
            statsCPU += CACurrentMediaTime() - start
            let elapsed = CACurrentMediaTime() - statsStart

            if elapsed >= 0.3 {
                fps = Double(statsFrames) / elapsed
                cpuMilliseconds = statsCPU / Double(statsFrames) * 1000
                objectCount = frame.snapshot.objects.count
                statsFrames = 0
                statsCPU = 0
                statsStart = CACurrentMediaTime()
            }
        } catch {
            configuration = applied
            report(error.localizedDescription)
            isRenderingPaused = true
            view.isPaused = true
        }
    }

    // MARK: - Session lifecycle

    public func activate() {
        stopped = false
        retry()
    }

    public func retry() {
        clock.reset()
        statsFrames = 0
        statsCPU = 0
        statsStart = CACurrentMediaTime()
        isRenderingPaused = false
    }

    public func shutdown() {
        guard !stopped else {
            return
        }

        stopped = true
        scheduler.stop(world: world)

        do {
            try renderer.waitUntilIdle()
        } catch {
            report(error.localizedDescription)
        }

        log.write(category: "Application", "Session stopped.")

        if let error = log.flush() {
            logger.error("Log file: \(error, privacy: .public)")
        }
    }

    // MARK: - Error reporting

    func report(_ message: String) {
        log.write(.error, category: "Application", message)
        refreshDiagnostics()

        if self.message != message {
            self.message = message
        }
    }
}
