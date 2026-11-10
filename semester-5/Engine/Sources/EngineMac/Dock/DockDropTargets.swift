import AppKit
import SwiftUI

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
