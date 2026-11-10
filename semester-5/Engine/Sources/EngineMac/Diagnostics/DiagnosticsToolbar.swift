import SwiftUI

// MARK: - Toolbar and tabs

@MainActor struct DiagnosticsToolbar: View {
    @ObservedObject var session: EngineSession
    @ObservedObject var dock: DiagnosticsDock

    var body: some View {
        HStack(spacing: 12) {
            Button {
                session.togglePause()
            } label: {
                Label(
                    session.simulationPaused ? "Resume" : "Pause",
                    systemImage: session.simulationPaused ? "play.fill" : "pause.fill")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button {
                session.stepFrame()
            } label: {
                Label("Step", systemImage: "forward.frame")
            }

            Button {
                session.captureFrame()
            } label: {
                Label("Capture frame", systemImage: "camera")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Xcode GPU trace…") {
                session.exportGPUTrace()
            }

            Menu {
                ForEach([DockPanel.console, .settings]) { panel in
                    Button(panel.title) {
                        dock.show(panel)
                    }
                }

                Divider()

                Button("Restore default layout") {
                    dock.reset()
                }
            } label: {
                Label("Panels", systemImage: "rectangle.3.group")
            }

            Menu {
                ForEach([DockPanel.profiler, .frame]) { panel in
                    Button(panel.title) {
                        dock.show(panel)
                    }
                }
            } label: {
                Label("Analysis", systemImage: "chart.xyaxis.line")
            }

            Spacer()

            if session.simulationPaused {
                Text("PAUSED")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.orange)
            }

            Button {
                dock.toggleDiagnostics()
            } label: {
                Label("Diagnostics", systemImage: "terminal")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
