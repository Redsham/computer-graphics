import AppKit
import SwiftUI

// MARK: - Tool content

@MainActor struct DockToolContent: View {
    @ObservedObject var session: EngineSession
    let panel: DockPanel
    let state: DiagnosticsViewState

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                tool
                    .frame(width: max(minimumWidth, geometry.size.width), height: geometry.size.height)
            }
        }
    }

    private var minimumWidth: CGFloat {
        switch panel {
        case .settings:
            0
        case .console:
            500
        case .profiler, .frame:
            960
        }
    }

    @ViewBuilder private var tool: some View {
        switch panel {
        case .console:
            ConsolePanel(session: session, state: state.console)
        case .profiler:
            ProfilerPanel(session: session, state: state.profiler)
        case .frame:
            FrameDebuggerPanel(session: session, state: state.frame)
        case .settings:
            RendererSettingsPanel(session: session)
        }
    }
}

// MARK: - Workspace chrome

@MainActor struct DockGroupView: View {
    @ObservedObject var dock: DiagnosticsDock
    let region: DockRegion

    private var panels: [DockPanel] {
        dock.layout.visiblePanels(in: region)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(panels) { panel in
                            DockTab(
                                dock: dock, panel: panel, region: region,
                                selected: selected == panel
                            )
                            .frame(width: panel == .frame ? 145 : 104, height: 30)
                            .contextMenu {
                                DockPanelActions(dock: dock, panel: panel)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if let selected {
                    Button {
                        dock.detach(selected)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .help("Detach selected panel")

                    Menu {
                        DockPanelActions(dock: dock, panel: selected)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22)

                    Button {
                        dock.hide(selected)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Hide selected panel")
                }
            }
            .buttonStyle(.borderless)
            .frame(height: 32)
            .padding(.horizontal, 8)
            .background(.bar)

            Divider()

            if let selected {
                DockPanelMount(dock: dock, panel: selected, region: region)
                    .id(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Dock \(region.rawValue)", systemImage: "rectangle.on.rectangle",
                    description: Text("Drop a tool tab here"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var selected: DockPanel? {
        dock.layout.selection(in: region)
    }
}

@MainActor struct FloatingDockPanel: View {
    @ObservedObject var dock: DiagnosticsDock
    let panel: DockPanel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DockTab(dock: dock, panel: panel, region: nil, selected: true)
                    .frame(width: 180, height: 30)

                Spacer()

                Menu("Dock to…") {
                    ForEach(DockRegion.allCases, id: \.self) { region in
                        Button(region.rawValue.capitalized) {
                            dock.dock(panel, in: region)
                        }
                    }
                }
                .fixedSize()

                Button("Return to workspace") {
                    dock.dock(panel, in: panel == .settings ? .right : .bottom)
                }
            }
            .frame(height: 32)
            .padding(.horizontal, 10)
            .background(.bar)

            Divider()

            DockPanelMount(dock: dock, panel: panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor struct DockPanelActions: View {
    let dock: DiagnosticsDock
    let panel: DockPanel

    var body: some View {
        Button("Open in separate window") {
            dock.detach(panel)
        }

        ForEach(DockRegion.allCases, id: \.self) { region in
            Button("Dock \(region.rawValue)") {
                dock.dock(panel, in: region)
            }
        }

        Divider()

        Button("Hide panel") {
            dock.hide(panel)
        }
    }
}
