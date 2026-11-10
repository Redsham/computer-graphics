import EngineCore
import EngineMetal
import Foundation

extension EngineSession {
    func registerDiagnosticsCommands() {
        registerCommand("stats", "Latest CPU/GPU time, waits, draw count and resident memory.") {
            session, _ in
            guard let frame = session.renderer.profiles.frames.last else {
                return "No frames yet."
            }

            return
                "Frame \(frame.id): CPU \(frame.cpuMilliseconds) ms, GPU \(frame.gpuMilliseconds.map { "\($0) ms" } ?? "pending"), wait \(frame.waitMilliseconds) ms, \(frame.drawCount) draws, \(frame.objectCount) objects, \(frame.resourceBytes) resident bytes."
        }
        registerCommand("profile", "profile on|off|clear") { session, args in
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
        registerCommand("passes", "Describe every registered pass and resource dependency.") { session, _ in
            session.renderer.passDescriptions(configuration: session.configuration).joined(
                separator: "\n")
        }
        registerCommand("entities", "List renderable ECS entity IDs.") { session, _ in
            session.world.entities(with: MeshRenderer.self).map { "Entity \($0.index):\($0.generation)" }
                .joined(separator: "\n")
        }
        registerCommand("log", "log debug|info|warning|error <category> <message>") { session, args in
            guard args.count >= 3, let level = LogLevel(rawValue: args[0]) else {
                throw EngineError.invalidConfiguration("Use log <level> <category> <message>")
            }

            session.log.write(level, category: args[1], args.dropFirst(2).joined(separator: " "))
            return ""
        }
        registerCommand("trace", "trace <new-file.gputrace> — capture one frame for Xcode.") {
            session, args in
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
}
