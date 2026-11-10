import AppKit
import EngineCore
import EngineMetal
import Metal
import UniformTypeIdentifiers

extension EngineSession {
    // MARK: - Diagnostics refresh

    public func refreshDiagnostics() {
        renderer.collectCompletedProfiles()

        if logRevision != log.revision {
            logEntries = log.entries
            logRevision = log.revision
        }

        profileFrames = renderer.profiles.frames
    }

    // MARK: - Playback and frame capture

    public func togglePause() {
        simulationPaused.toggle()
        stepRequested = false
        clock.reset()
        log.write(category: "Console", simulationPaused ? "Simulation paused." : "Simulation resumed.")
        refreshDiagnostics()
    }

    public func stepFrame() {
        if diagnosticsTab == "Frame", capturedFrame != nil {
            do {
                try renderer.requestCapture()
            } catch {
                report(error.localizedDescription)
                return
            }
        }

        simulationPaused = true
        stepRequested = true
        clock.reset()
    }

    public func captureFrame() {
        do {
            try renderer.requestCapture()
            stepRequested = true
        } catch {
            report(error.localizedDescription)
        }

        refreshDiagnostics()
    }

    // MARK: - Console commands

    public func executeCommand(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        log.write(category: "Console", "> \(input)")

        do {
            let output = try commands.execute(input)

            if !output.isEmpty {
                log.write(category: "Console", output)
            }
        } catch {
            log.write(.error, category: "Console", error.localizedDescription)
        }

        refreshDiagnostics()
    }

    func configureCommands() {
        func command(
            _ name: String, _ help: String,
            _ run: @escaping @MainActor (EngineSession, [String]) throws -> String
        ) {
            commands.register(name, help: help) { [weak self] args in
                guard let self else {
                    return "Session closed."
                }

                return try run(self, args)
            }
        }

        command("help", "List commands. Use quotes for arguments containing spaces.") { session, _ in
            session.commands.help
        }
        command("echo", "echo <text>") { _, args in args.joined(separator: " ") }
        command("clear", "Clear the in-memory journal; disk log remains.") { session, _ in
            session.log.clear()
            return "Journal cleared."
        }
        command("pause", "Pause simulation and drawing.") { session, _ in
            if !session.simulationPaused {
                session.togglePause()
            }

            return "Paused."
        }
        command("resume", "Resume simulation; retry a rendering error.") { session, _ in
            session.simulationPaused = false
            session.stepRequested = false
            session.retry()
            return "Resumed."
        }
        command("step", "Advance exactly one simulation/render frame.") { session, _ in
            session.stepFrame()
            return "One frame requested."
        }
        command("capture", "Capture the next frame and freeze it in Frame Debugger.") { session, _ in
            session.captureFrame()
            return "Capture requested."
        }
        command("reset", "Restore bundled render/camera settings.") { session, _ in
            session.resetSettings()
            session.stepRequested = true
            return "Defaults restored."
        }
        command("get", "Show all renderer and camera settings.") { session, _ in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: try encoder.encode(session.configuration), as: UTF8.self)
        }
        command("set", "set fps|msaa|exposure|fov|speed|wireframe <value>; set background <r> <g> <b>") {
            session, args in
            guard args.count >= 2 else {
                throw EngineError.invalidConfiguration("Usage: set <key> <value>")
            }

            var config = session.configuration
            let value = args[1]

            switch args[0] {
            case "fps":
                guard let number = Int(value) else {
                    throw EngineError.invalidConfiguration("FPS must be an integer.")
                }

                config.targetFPS = number
            case "msaa":
                guard let number = Int(value) else {
                    throw EngineError.invalidConfiguration("MSAA must be 1 or 4.")
                }

                config.sampleCount = number
            case "wireframe":
                guard ["on", "off", "true", "false", "1", "0"].contains(value) else {
                    throw EngineError.invalidConfiguration("Use on/off.")
                }

                config.wireframe = ["on", "true", "1"].contains(value)
            case "background":
                guard args.count == 4, let r = Float(args[1]), let g = Float(args[2]),
                    let b = Float(args[3])
                else {
                    throw EngineError.invalidConfiguration(
                        "Use set background <r> <g> <b> in linear RGB 0...1.")
                }

                config.background = SIMD3(r, g, b)
            case "exposure", "fov", "speed":
                guard let number = Float(value) else {
                    throw EngineError.invalidConfiguration("Expected a number.")
                }

                if args[0] == "exposure" {
                    config.exposure = number
                }

                if args[0] == "fov" {
                    config.fieldOfView = number
                }

                if args[0] == "speed" {
                    config.cameraSpeed = number
                }
            default:
                throw EngineError.invalidConfiguration("Unknown setting. Use help.")
            }

            session.configuration = try config.validated()

            if session.simulationPaused {
                session.stepRequested = true
            }

            return "\(args[0]) = \(args.dropFirst().joined(separator: " "))"
        }
        command("stats", "Latest CPU/GPU time, waits, draw count and resident memory.") { session, _ in
            guard let frame = session.renderer.profiles.frames.last else {
                return "No frames yet."
            }

            return
                "Frame \(frame.id): CPU \(frame.cpuMilliseconds) ms, GPU \(frame.gpuMilliseconds.map { "\($0) ms" } ?? "pending"), wait \(frame.waitMilliseconds) ms, \(frame.drawCount) draws, \(frame.objectCount) objects, \(frame.resourceBytes) resident bytes."
        }
        command("profile", "profile on|off|clear") { session, args in
            guard let mode = args.first, ["on", "off", "clear"].contains(mode) else {
                throw EngineError.invalidConfiguration("Use profile on|off|clear")
            }

            if mode == "clear" {
                session.renderer.profiles.clear()
            } else {
                session.renderer.profilingEnabled = mode == "on"
            }

            return "GPU pass profiling: \(session.renderer.profilingEnabled ? "on" : "off")."
        }
        command("passes", "Describe every registered pass and resource dependency.") { session, _ in
            session.renderer.passDescriptions(configuration: session.configuration).joined(
                separator: "\n")
        }
        command("entities", "List renderable ECS entity IDs.") { session, _ in
            session.world.entities(with: MeshRenderer.self).map { "Entity \($0.index):\($0.generation)" }
                .joined(separator: "\n")
        }
        command("log", "log debug|info|warning|error <category> <message>") { session, args in
            guard args.count >= 3, let level = LogLevel(rawValue: args[0]) else {
                throw EngineError.invalidConfiguration("Use log <level> <category> <message>")
            }

            session.log.write(level, category: args[1], args.dropFirst(2).joined(separator: " "))
            return ""
        }
        command("trace", "trace <new-file.gputrace> — capture one frame for Xcode.") { session, args in
            guard args.count == 1 else {
                throw EngineError.invalidConfiguration("Use trace <path.gputrace>")
            }

            let url = URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath)

            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw EngineError.unavailable("Choose a new path; existing traces are not overwritten.")
            }

            try session.renderer.requestGPUTrace(url: url)
            session.stepRequested = true
            return "GPU trace armed."
        }
    }

    // MARK: - Export

    public func exportLog() {
        save(name: "EngineLog.json", type: .json) { try self.log.exportJSON() }
    }

    public func exportProfiles(_ frames: [FrameProfile]? = nil) {
        save(name: "Profile.json", type: .json) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            return try encoder.encode(frames ?? self.renderer.profiles.frames)
        }
    }

    public func exportCapture() {
        save(name: "Frame-\(capturedFrame?.id ?? 0).json", type: .json) {
            guard let capture = self.capturedFrame else {
                throw EngineError.unavailable("Capture a frame first.")
            }

            return try capture.exportJSON()
        }
    }

    public func exportBuffer(_ buffer: CapturedBuffer) {
        save(name: "Buffer.bin", type: .data) { buffer.bytes }
    }

    public func exportTexture(_ texture: CapturedTexture) {
        save(name: "Texture.bin", type: .data) { texture.bytes }
    }

    public func exportGPUTrace() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Frame.gputrace"
        panel.canCreateDirectories = true
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else {
                return
            }

            do {
                try self.renderer.requestGPUTrace(url: url)
                self.stepRequested = true
                self.refreshDiagnostics()
            } catch {
                self.report(error.localizedDescription)
            }
        }
    }

    // MARK: - Save dialog

    private func save(name: String, type: UTType, data: @escaping @MainActor () throws -> Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else {
                return
            }

            do {
                try data().write(to: url, options: .atomic)
                self.log.write(category: "Export", url.path)
                self.refreshDiagnostics()
            } catch {
                self.report(error.localizedDescription)
            }
        }
    }
}
