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
            let cube = try session.renderer.resources.makeCube()
            let material = session.renderer.resources.makeMaterial(
                Material(baseColor: SIMD3(0.12, 0.55, 0.85)))
            let object = session.world.create()
            session.world.set(Transform(), for: object)
            session.world.set(WorldTransform(Transform().matrix), for: object)
            session.world.set(MeshRenderer(mesh: cube, material: material), for: object)
            session.world.set(Spin(), for: object)
            let camera = session.world.create()
            session.world.set(Transform(position: SIMD3(0, 0, 4)), for: camera)
            session.world.set(Camera(), for: camera)
            let light = session.world.create()
            session.world.set(DirectionalLight(), for: light)
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
