import AppKit
import SwiftUI

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
