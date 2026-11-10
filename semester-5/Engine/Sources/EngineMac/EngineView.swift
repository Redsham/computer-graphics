import EngineCore
import MetalKit
import SwiftUI
import simd

// MARK: - Metal viewport bridge

@MainActor private struct MetalViewport: NSViewRepresentable {
    @ObservedObject var session: EngineSession

    func makeNSView(context: Context) -> MTKView {
        let view = EngineMetalView(frame: .zero, device: session.renderer.metal.device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.framebufferOnly = false
        view.preferredFramesPerSecond = session.configuration.targetFPS
        view.delegate = session
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        view.isPaused = session.viewportPaused
    }

    static func dismantleNSView(_ view: MTKView, coordinator: ()) {
        view.isPaused = true
        view.delegate = nil
    }
}

// MARK: - Viewport and HUD

@MainActor struct EngineViewport: View {
    @ObservedObject var session: EngineSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalViewport(session: session)

            VStack(alignment: .leading, spacing: 5) {
                Text("METAL 4")
                    .font(.caption.bold())
                    .foregroundStyle(.mint)

                Text(
                    session.simulationPaused
                        ? String(
                            format: "Paused · CPU %.2f ms · objects: %d", session.cpuMilliseconds,
                            session.objectCount)
                        : String(
                            format: "%.0f FPS · CPU %.2f ms · objects: %d", session.fps,
                            session.cpuMilliseconds, session.objectCount)
                )
                .font(.system(.caption, design: .monospaced))

                Text("WASD · Q/E · Right-drag to look")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }

    }
}

// MARK: - Application layout

@MainActor public struct EngineView: View {
    @ObservedObject private var session: EngineSession
    @StateObject private var dock: DiagnosticsDock

    public init(session: EngineSession) {
        self.session = session
        _dock = StateObject(wrappedValue: DiagnosticsDock(session: session))
    }

    public var body: some View {
        VStack(spacing: 0) {
            DiagnosticsToolbar(session: session, dock: dock)

            Divider()

            DockWorkspace(session: session, dock: dock)
        }
        .frame(minWidth: 1000, minHeight: 640)
        .onAppear {
            session.diagnosticsDock = dock
            session.activate()
            dock.restoreWindows()
        }
        .onDisappear {
            dock.shutdown()
            session.diagnosticsDock = nil
            session.shutdown()
        }
    }
}
