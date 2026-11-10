import AppKit
import Combine
import SwiftUI

// MARK: - Dock ownership

@MainActor final class DiagnosticsDock: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var layout: DockLayout
    @Published private(set) var dragging: DockPanel?

    let identifier = UUID().uuidString
    let viewState = DiagnosticsViewState()
    let storageKey: String
    weak var workspace: DockWorkspaceController?
    private weak var session: EngineSession?
    private let defaults: UserDefaults
    private var hosts: [DockPanel: NSHostingView<AnyView>] = [:]
    private(set) var windows: [DockPanel: NSWindow] = [:]
    private var restoring = false
    private var dragSource: DockTabButton?
    private var dragPreview: NSPanel?
    private var escapeMonitor: Any?

    init(session: EngineSession, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        storageKey = "\(session.settingsName).Dock.v1"

        if let data = defaults.data(forKey: storageKey) {
            do {
                layout = try JSONDecoder().decode(DockLayout.self, from: data).validated()
            } catch {
                layout = .initial
                session.log.write(
                    .warning, category: "Dock", "Saved layout is invalid; using the default layout.")
            }
        } else {
            layout = .initial
        }

        super.init()
    }

    func content(for panel: DockPanel) -> NSView {
        if let host = hosts[panel] {
            return host
        }

        guard let session else {
            return NSView()
        }

        let host = NSHostingView(
            rootView: AnyView(DockToolContent(session: session, panel: panel, state: viewState)))
        host.sizingOptions = []
        hosts[panel] = host
        return host
    }

    @discardableResult
    func mount(_ panel: DockPanel, in container: PanelContainer, region: DockRegion?) -> Bool {
        if let region {
            guard layout.region(of: panel) == region, layout.selection(in: region) == panel else {
                return false
            }
        } else {
            guard layout.floating[panel] != nil else {
                return false
            }
        }

        container.mount(content(for: panel))
        return true
    }

    func select(_ panel: DockPanel, in region: DockRegion) {
        guard layout.groups[region]?.panels.contains(panel) == true else {
            return
        }

        layout.groups[region]?.selected = panel
        changed()
    }

    func show(_ panel: DockPanel) {
        if let window = windows[panel] {
            layout.diagnosticsHidden = false
            changed()
            window.makeKeyAndOrderFront(nil)
            return
        }

        if let region = layout.region(of: panel) {
            layout.groups[region]?.selected = panel
            layout.diagnosticsHidden = false
            changed()
        } else {
            dock(panel, in: panel == .settings ? .right : .bottom)
        }
    }

    func dock(_ panel: DockPanel, in region: DockRegion, before target: DockPanel? = nil) {
        guard target != panel else {
            return
        }

        releaseWindow(for: panel)
        layout.dock(panel, in: region, before: target)
        changed()
    }

    func hide(_ panel: DockPanel) {
        releaseWindow(for: panel)
        layout.remove(panel)
        changed()
    }

    func toggleDiagnostics() {
        layout.diagnosticsHidden.toggle()

        if !layout.diagnosticsHidden,
            !DockPanel.allCases.filter({
                $0 != .settings
            }).contains(where: {
                layout.region(of: $0) != nil || layout.floating[$0] != nil
            })
        {
            layout.dock(.console, in: .bottom)
        }

        for (panel, window) in windows where panel != .settings {
            if layout.diagnosticsHidden {
                window.orderOut(nil)
            } else {
                window.orderFront(nil)
            }
        }

        changed()
    }

    // MARK: - Floating windows

    func detach(_ panel: DockPanel, at point: NSPoint? = nil) {
        if let window = windows[panel] {
            if let point {
                window.setFrameTopLeftPoint(point)
            }

            window.makeKeyAndOrderFront(nil)
            return
        }

        let origin = point ?? workspace?.view.window?.frame.origin ?? NSPoint(x: 160, y: 240)
        let frame = DockWindowFrame(x: origin.x, y: origin.y - 420, width: 900, height: 480)
        layout.detach(panel, frame: frame)
        layout.diagnosticsHidden = false
        makeWindow(for: panel, frame: frame)
        changed()
    }

    private func makeWindow(for panel: DockPanel, frame: DockWindowFrame) {
        guard windows[panel] == nil else {
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(panel.title) — Engine Diagnostics"
        window.identifier = NSUserInterfaceItemIdentifier("\(storageKey).\(panel.rawValue)")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 300)
        window.delegate = self
        let content = NSHostingView(rootView: FloatingDockPanel(dock: self, panel: panel))
        content.sizingOptions = []
        window.contentView = content

        // Restore to an available display even when the previous monitor was disconnected.
        let screen =
            NSScreen.screens.first {
                $0.visibleFrame.intersects(window.frame)
            } ?? NSScreen.main

        if let available = screen?.visibleFrame {
            var rect = window.frame
            rect.size.width = min(rect.width, available.width)
            rect.size.height = min(rect.height, available.height)
            rect.origin.x = min(max(rect.minX, available.minX), available.maxX - rect.width)
            rect.origin.y = min(max(rect.minY, available.minY), available.maxY - rect.height)
            window.setFrame(rect, display: false)
        }

        windows[panel] = window
        window.makeKeyAndOrderFront(nil)
    }

    func restoreWindows() {
        guard windows.isEmpty else {
            return
        }

        restoring = true

        for (panel, frame) in layout.floating {
            makeWindow(for: panel, frame: frame)

            if layout.diagnosticsHidden {
                windows[panel]?.orderOut(nil)
            }
        }

        restoring = false
    }

    private func releaseWindow(for panel: DockPanel) {
        guard let window = windows.removeValue(forKey: panel) else {
            return
        }

        window.delegate = nil
        hosts[panel]?.removeFromSuperview()
        window.contentView = nil
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let panel = windows.first(where: {
            $0.value === sender
        })?.key {
            // Closing a floating tool returns it to the workspace rather than losing it.
            dock(panel, in: panel == .settings ? .right : .bottom)
        }

        return false
    }

    func windowDidMove(_ notification: Notification) {
        rememberFrame(notification)
    }

    func windowDidResize(_ notification: Notification) {
        rememberFrame(notification)
    }

    private func rememberFrame(_ notification: Notification) {
        guard !restoring, let window = notification.object as? NSWindow,
            let panel = windows.first(where: {
                $0.value === window
            })?.key
        else {
            return
        }

        let rect = window.contentRect(forFrameRect: window.frame)
        layout.floating[panel] = DockWindowFrame(
            x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        save()
    }

    // MARK: - Dragging and persistence

    func beginDrag(_ panel: DockPanel, source: DockTabButton) {
        dragging = panel
        dragSource = source
        let preview = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 34),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false
        preview.ignoresMouseEvents = true
        preview.level = .floating
        preview.alphaValue = 0.85
        preview.contentView = NSHostingView(
            rootView: Label(panel.title, systemImage: panel.symbol)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial))
        dragPreview = preview
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelDrag(); return nil
            }

            return event
        }
        workspace?.updateDropTargets()
    }

    private func destination(at point: NSPoint) -> (region: DockRegion, before: DockPanel?)? {
        let top = NSApp.orderedWindows.first {
            $0 !== dragPreview && $0.isVisible && !$0.isMiniaturized && $0.frame.contains(point)
        }

        guard top === workspace?.view.window else {
            return nil
        }

        return workspace?.destination(at: point)
    }

    func updateDrag(at point: NSPoint) {
        dragPreview?.setFrameTopLeftPoint(NSPoint(x: point.x + 12, y: point.y - 12))
        dragPreview?.orderFrontRegardless()
        workspace?.highlight(destination(at: point)?.region)
    }

    func finishDrag(at point: NSPoint) {
        guard let panel = dragging else {
            return
        }

        let target = destination(at: point)
        let insideWindow =
            ([workspace?.view.window].compactMap {
                $0
            } + Array(windows.values))
            .contains {
                $0.isVisible && $0.frame.contains(point)
            }
        cancelDrag()

        if let target {
            dock(panel, in: target.region, before: target.before)
        } else if !insideWindow {
            detach(panel, at: point)
        }
    }

    func cancelDrag() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }

        escapeMonitor = nil
        dragging = nil
        dragSource = nil
        dragPreview?.close()
        dragPreview = nil
        workspace?.highlight(nil)
        workspace?.updateDropTargets()
    }

    func reset() {
        cancelDrag()

        for panel in Array(windows.keys) {
            releaseWindow(for: panel)
        }

        layout = .initial
        workspace?.resetDividers()
        changed()
    }

    func shutdown() {
        cancelDrag()
        save()

        for panel in Array(windows.keys) {
            releaseWindow(for: panel)
        }

        hosts.removeAll()
    }

    private func changed() {
        workspace?.updateLayout()
        save()
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(layout), forKey: storageKey)
        } catch {
            session?.log.write(
                .error, category: "Dock", "Could not save layout: \(error.localizedDescription)")
        }
    }
}
