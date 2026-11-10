import AppKit
import Combine
import SwiftUI

// MARK: - Resizable workspace

@MainActor struct DockWorkspace: NSViewControllerRepresentable {
    let session: EngineSession
    let dock: DiagnosticsDock

    func makeNSViewController(context: Context) -> DockWorkspaceController {
        DockWorkspaceController(session: session, dock: dock)
    }

    func updateNSViewController(_ controller: DockWorkspaceController, context: Context) {
        controller.updateLayout()
    }
}

@MainActor final class DockWorkspaceController: NSSplitViewController {
    private let dock: DiagnosticsDock
    private let horizontal = NSSplitViewController()
    private let viewport: DockViewportContainer
    private var items: [DockRegion: NSSplitViewItem] = [:]
    private var firstLayout = true

    init(session: EngineSession, dock: DiagnosticsDock) {
        self.dock = dock
        viewport = DockViewportContainer(session: session, dock: dock)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dock.workspace = self
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autosaveName = dock.storageKey + ".vertical"
        horizontal.splitView.isVertical = true
        horizontal.splitView.dividerStyle = .thin
        horizontal.splitView.autosaveName = dock.storageKey + ".horizontal"

        let left = group(.left, minimum: 280, maximum: 650)
        horizontal.addSplitViewItem(left)
        let center = NSViewController()
        center.view = viewport
        let centerItem = NSSplitViewItem(viewController: center)
        centerItem.minimumThickness = 360
        centerItem.holdingPriority = .defaultLow
        horizontal.addSplitViewItem(centerItem)
        horizontal.addSplitViewItem(group(.right, minimum: 280, maximum: 650))

        let top = NSSplitViewItem(viewController: horizontal)
        top.minimumThickness = 260
        top.holdingPriority = .defaultLow
        addSplitViewItem(top)
        addSplitViewItem(group(.bottom, minimum: 220, maximum: 800))
        updateLayout()
    }

    private func group(_ region: DockRegion, minimum: CGFloat, maximum: CGFloat) -> NSSplitViewItem {
        let controller = NSViewController()
        let container = DockDropContainer(dock: dock, region: region)
        let content = NSHostingView(rootView: DockGroupView(dock: dock, region: region))
        content.sizingOptions = []
        container.mount(content)
        controller.view = container
        let item = NSSplitViewItem(viewController: controller)
        item.canCollapse = true
        item.minimumThickness = minimum
        item.maximumThickness = maximum
        item.holdingPriority = .defaultHigh
        items[region] = item
        return item
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard firstLayout, view.bounds.width > 0 else {
            return
        }

        firstLayout = false

        // NSSplitView restores saved divider positions; initialize only a new workspace.
        if UserDefaults.standard.object(
            forKey: "NSSplitView Subview Frames " + dock.storageKey + ".horizontal") == nil
        {
            resetDividers()
        }
    }

    func resetDividers() {
        horizontal.splitView.setPosition(300, ofDividerAt: 0)
        horizontal.splitView.setPosition(max(360, horizontal.view.bounds.width - 300), ofDividerAt: 1)
        splitView.setPosition(max(260, view.bounds.height - 340), ofDividerAt: 0)
        updateLayout()
    }

    func updateLayout() {
        for region in DockRegion.allCases {
            let panels = dock.layout.groups[region]?.panels ?? []
            let visible = panels.contains {
                !dock.layout.diagnosticsHidden || $0 == .settings
            }
            items[region]?.isCollapsed = !visible
        }

        updateDropTargets()
    }

    func destination(at screenPoint: NSPoint) -> (region: DockRegion, before: DockPanel?)? {
        if let region = viewport.destination(at: screenPoint) {
            return (region, nil)
        }

        guard let window = view.window else {
            return nil
        }

        let point = window.convertPoint(fromScreen: screenPoint)

        for region in DockRegion.allCases {
            guard let item = items[region], !item.isCollapsed else {
                continue
            }

            let container = item.viewController.view

            guard container.bounds.contains(container.convert(point, from: nil)) else {
                continue
            }

            func tab(in node: NSView) -> DockPanel? {
                if let tab = node as? DockTabButton, tab.bounds.contains(tab.convert(point, from: nil)) {
                    return tab.panel
                }

                return node.subviews.lazy.compactMap {
                    tab(in: $0)
                }.first
            }

            return (region, tab(in: container))
        }

        return nil
    }

    func highlight(_ region: DockRegion?) {
        for (key, item) in items {
            (item.viewController.view as? DockDropContainer)?.highlight(key == region)
        }

        viewport.highlight(region)
    }

    func updateDropTargets() {
        viewport.showDropTargets(dock.dragging != nil)
    }
}

// MARK: - Drop destinations

@MainActor final class DockDropContainer: PanelContainer {
    init(dock: DiagnosticsDock, region: DockRegion) {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func highlight(_ active: Bool) {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = active ? 3 : 0
    }
}

@MainActor final class DockViewportContainer: NSView {
    private let content: NSHostingView<EngineViewport>
    private var targets: [DockRegion: DockDropContainer] = [:]

    init(session: EngineSession, dock: DiagnosticsDock) {
        content = NSHostingView(rootView: EngineViewport(session: session))
        super.init(frame: .zero)
        content.sizingOptions = []
        addSubview(content)

        for region in DockRegion.allCases {
            let target = DockDropContainer(dock: dock, region: region)
            let label = NSTextField(labelWithString: "Dock \(region.rawValue)")
            label.alignment = .center
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = .controlAccentColor
            let background = NSVisualEffectView()
            background.material = .hudWindow
            background.blendingMode = .withinWindow
            background.state = .active
            target.mount(background)
            label.frame = NSRect(x: 0, y: 30, width: 120, height: 22)
            background.addSubview(label)
            target.isHidden = true
            targets[region] = target
            addSubview(target)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        targets[.left]?.frame = NSRect(x: 12, y: bounds.midY - 42, width: 120, height: 84)
        targets[.right]?.frame = NSRect(x: bounds.width - 132, y: bounds.midY - 42, width: 120, height: 84)
        targets[.bottom]?.frame = NSRect(x: bounds.midX - 60, y: 12, width: 120, height: 84)
    }

    func destination(at screenPoint: NSPoint) -> DockRegion? {
        guard let window else {
            return nil
        }

        let point = window.convertPoint(fromScreen: screenPoint)
        return targets.first { _, target in
            !target.isHidden && target.bounds.contains(target.convert(point, from: nil))
        }?.key
    }

    func highlight(_ region: DockRegion?) {
        for (key, target) in targets {
            target.highlight(key == region)
        }
    }

    func showDropTargets(_ visible: Bool) {
        targets.values.forEach {
            $0.isHidden = !visible
        }
    }
}
