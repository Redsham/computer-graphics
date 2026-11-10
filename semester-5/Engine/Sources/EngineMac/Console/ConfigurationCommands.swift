import EngineCore
import EngineMetal
import Foundation

extension EngineSession {
    func registerConfigurationCommands() {
        registerCommand("get", "Show all renderer and camera settings.") { session, _ in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: try encoder.encode(session.configuration), as: UTF8.self)
        }
        registerCommand(
            "set", "set fps|msaa|exposure|fov|speed|wireframe <value>; set background <r> <g> <b>"
        ) {
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
    }
}
