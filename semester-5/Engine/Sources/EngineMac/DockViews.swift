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

// MARK: - Stable panel hosts

/// The same hosting view moves between containers, retaining SwiftUI state and subscriptions.
@MainActor struct DockPanelMount: NSViewRepresentable {
    let dock: DiagnosticsDock
    let panel: DockPanel
    var region: DockRegion? = nil

    func makeNSView(context: Context) -> PanelContainer {
        let container = PanelContainer()
        mountIfOwned(container)
        return container
    }

    func updateNSView(_ container: PanelContainer, context: Context) {
        mountIfOwned(container)
    }

    private func mountIfOwned(_ container: PanelContainer) {
        // SwiftUI can finish updating an outgoing tab after a new window already mounted its content.
        // Only the current owner may move the persistent hosting view.
        dock.mount(panel, in: container, region: region)
    }

    static func dismantleNSView(_ container: PanelContainer, coordinator: ()) {
        container.subviews.forEach {
            $0.removeFromSuperview()
        }
    }
}

@MainActor class PanelContainer: NSView {
    func mount(_ content: NSView) {
        guard content.superview !== self else {
            return
        }

        subviews.forEach {
            $0.removeFromSuperview()
        }
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        content.frame = bounds
        addSubview(content)
    }
}

// MARK: - Native tab drag source

@MainActor struct DockTab: NSViewRepresentable {
    let dock: DiagnosticsDock
    let panel: DockPanel
    let region: DockRegion?
    let selected: Bool

    func makeNSView(context: Context) -> DockTabButton {
        DockTabButton()
    }

    func updateNSView(_ button: DockTabButton, context: Context) {
        button.dock = dock
        button.panel = panel
        button.region = region
        button.title = panel.title
        button.image = NSImage(systemSymbolName: panel.symbol, accessibilityDescription: nil)
        button.state = selected ? .on : .off
        button.toolTip = "Drag to dock; drag outside the window to detach. Double-click to detach."
        button.setAccessibilityLabel(panel.title + " dock tab")
    }
}

@MainActor final class DockTabButton: NSButton {
    weak var dock: DiagnosticsDock?
    var panel: DockPanel = .console
    var region: DockRegion?
    private var mouseDownEvent: NSEvent?
    private var moving = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .recessed
        setButtonType(.pushOnPushOff)
        imagePosition = .imageLeading
        font = .systemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(activateTab)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func activateTab() {
        if let region {
            dock?.select(panel, in: region)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let dock else {
            return
        }

        if event.clickCount == 2 {
            dock.detach(panel); return
        }

        mouseDownEvent = event
        moving = false
        activateTab()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dock, let start = mouseDownEvent, let window else {
            return
        }

        if !moving {
            guard
                hypot(
                    event.locationInWindow.x - start.locationInWindow.x,
                    event.locationInWindow.y - start.locationInWindow.y) >= 5
            else {
                return
            }

            moving = true
            dock.beginDrag(panel, source: self)
        }

        dock.updateDrag(at: window.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseUp(with event: NSEvent) {
        if moving, let window {
            dock?.finishDrag(at: window.convertPoint(toScreen: event.locationInWindow))
        }

        mouseDownEvent = nil
        moving = false
    }
}
