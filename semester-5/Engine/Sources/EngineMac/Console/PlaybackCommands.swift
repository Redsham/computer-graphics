import EngineCore
import EngineMetal
import Foundation

extension EngineSession {
    func registerPlaybackCommands() {
        registerCommand("help", "List commands. Use quotes for arguments containing spaces.") { session, _ in
            session.commands.help
        }
        registerCommand("echo", "echo <text>") { _, args in args.joined(separator: " ") }
        registerCommand("clear", "Clear the in-memory journal; disk log remains.") { session, _ in
            session.log.clear()
            return "Journal cleared."
        }
        registerCommand("pause", "Pause simulation and drawing.") { session, _ in
            if !session.simulationPaused {
                session.togglePause()
            }

            return "Paused."
        }
        registerCommand("resume", "Resume simulation; retry a rendering error.") { session, _ in
            session.simulationPaused = false
            session.stepRequested = false
            session.retry()
            return "Resumed."
        }
        registerCommand("step", "Advance exactly one simulation/render frame.") { session, _ in
            session.stepFrame()
            return "One frame requested."
        }
        registerCommand("capture", "Capture the next frame and freeze it in Frame Debugger.") { session, _ in
            session.captureFrame()
            return "Capture requested."
        }
        registerCommand("reset", "Restore bundled render/camera settings.") { session, _ in
            session.resetSettings()
            session.stepRequested = true
            return "Defaults restored."
        }
    }
}
