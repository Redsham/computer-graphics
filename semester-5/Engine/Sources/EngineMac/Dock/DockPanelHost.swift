import AppKit
import SwiftUI

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
