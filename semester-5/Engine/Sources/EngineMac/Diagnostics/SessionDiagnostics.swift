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

        if profileRevision != renderer.profiles.revision {
            profileFrames = renderer.profiles.frames
            profileRevision = renderer.profiles.revision
        }
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
        if diagnosticsDock?.layout.isVisible(.frame) == true, capturedFrame != nil {
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
}
