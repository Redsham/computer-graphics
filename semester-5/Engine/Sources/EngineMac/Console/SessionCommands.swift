import EngineCore
import EngineMetal
import Foundation

extension EngineSession {
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
        registerPlaybackCommands()
        registerConfigurationCommands()
        registerDiagnosticsCommands()
    }

    func registerCommand(
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

}
