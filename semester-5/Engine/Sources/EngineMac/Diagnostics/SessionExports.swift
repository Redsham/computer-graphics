import AppKit
import EngineCore
import EngineMetal
import Metal
import UniformTypeIdentifiers

extension EngineSession {
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
