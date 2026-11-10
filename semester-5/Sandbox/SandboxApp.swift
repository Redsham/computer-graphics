import EngineCore
import EngineMac
import SwiftUI

@main
struct SandboxApp: App {
    private let session: EngineSession?
    private let startupError: String?

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "DefaultConfiguration", withExtension: "json")
            else {
                throw EngineError.unavailable(
                    "Default configuration is missing from the application bundle.")
            }

            let session = try EngineSession(
                defaultsData: Data(contentsOf: url), settingsName: "GraphicsEngine.Sandbox",
                systems: [CameraControlSystem(), SpinSystem(), TransformSystem(), RenderExtractionSystem()])
            try SandboxScene.populate(session)
            self.session = session
            startupError = nil
        } catch {
            session = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        Window("Engine Sandbox", id: "sandbox") {
            if let session {
                EngineView(session: session)
            } else {
                ContentUnavailableView(
                    "Unable to start Metal engine", systemImage: "exclamationmark.triangle",
                    description: Text(startupError ?? "Unknown error")
                )
                .frame(width: 600, height: 300)
            }
        }.defaultSize(width: 1200, height: 760)
    }
}
