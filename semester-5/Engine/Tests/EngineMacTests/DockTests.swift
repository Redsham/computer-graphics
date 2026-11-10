import XCTest
import AppKit
import SwiftUI
import EngineCore
import Metal
@testable import EngineMac

final class DockTests: XCTestCase {
    private let windowFrame = DockWindowFrame(x: 100, y: 100, width: 900, height: 480)

    func testMoveBetweenRegionsAndReorderWithoutDuplicatingPanels() throws {
        var layout = DockLayout.initial
        layout.dock(.profiler, in: .left)
        XCTAssertEqual(layout.groups[.left]?.panels, [.profiler])
        XCTAssertFalse(layout.groups[.bottom]?.panels.contains(.profiler) ?? true)
        layout.dock(.frame, in: .bottom, before: .console)
        XCTAssertEqual(layout.groups[.bottom]?.panels, [.frame, .console])
        XCTAssertEqual(layout.groups[.bottom]?.selected, .frame)
        layout.dock(.frame, in: .bottom, before: .frame)
        XCTAssertEqual(try layout.validated(), layout)
    }

    func testDetachReturnAndHideMaintainSelection() throws {
        var layout = DockLayout.initial
        layout.detach(.console, frame: windowFrame)
        XCTAssertNil(layout.region(of: .console))
        XCTAssertEqual(layout.floating[.console], windowFrame)
        XCTAssertEqual(layout.groups[.bottom]?.selected, .profiler)
        layout.dock(.console, in: .right)
        XCTAssertNil(layout.floating[.console])
        XCTAssertEqual(layout.groups[.right]?.selected, .console)
        layout.remove(.console)
        XCTAssertEqual(layout.groups[.right]?.selected, .settings)
        XCTAssertFalse(layout.isVisible(.console))
        XCTAssertEqual(try layout.validated(), layout)
    }

    func testLayoutRoundTripPreservesHiddenToolsFloatingWindowsAndOrder() throws {
        var layout = DockLayout.initial
        layout.detach(.frame, frame: windowFrame)
        layout.dock(.profiler, in: .left)
        layout.remove(.console)
        layout.diagnosticsHidden = true
        let data = try JSONEncoder().encode(layout)
        let restored = try JSONDecoder().decode(DockLayout.self, from: data).validated()
        XCTAssertEqual(restored, layout)
        XCTAssertFalse(restored.isVisible(.profiler))
        XCTAssertFalse(restored.isVisible(.frame))
        XCTAssertTrue(restored.isVisible(.settings))
    }

    func testRejectsDuplicateOwnershipInvalidSelectionAndInvalidWindowFrames() {
        var layout = DockLayout.initial
        layout.groups[.left] = DockGroup(panels: [.console], selected: .console)
        XCTAssertThrowsError(try layout.validated())
        layout = .initial
        layout.floating[.console] = windowFrame
        XCTAssertThrowsError(try layout.validated())
        layout = .initial
        layout.groups[.left] = DockGroup(panels: [], selected: .profiler)
        XCTAssertThrowsError(try layout.validated())
        layout = .initial
        layout.detach(.profiler, frame: DockWindowFrame(x: .nan, y: 0, width: 0, height: 0))
        XCTAssertThrowsError(try layout.validated())
    }

    func testHiddenDiagnosticsKeepRendererAccessibleInMixedTabGroup() {
        var layout = DockLayout.initial
        layout.dock(.console, in: .right)
        layout.diagnosticsHidden = true
        XCTAssertEqual(layout.visiblePanels(in: .right), [.settings])
        XCTAssertEqual(layout.selection(in: .right), .settings)
        XCTAssertTrue(layout.isVisible(.settings))
        XCTAssertFalse(layout.isVisible(.console))
    }

    func testLegacyConsoleAndLogTabsMergeWithoutResettingLayout() throws {
        let data = Data(
            #"""
            {
                "groups": [
                    "left", {"panels": ["profiler"], "selected": "profiler"},
                    "bottom", {"panels": ["console", "log", "frame"], "selected": "log"}
                ],
                "floating": [],
                "diagnosticsHidden": false
            }
            """#.utf8)
        let layout = try JSONDecoder().decode(DockLayout.self, from: data).validated()

        XCTAssertEqual(layout.groups[.bottom]?.panels, [.console, .frame])
        XCTAssertEqual(layout.groups[.bottom]?.selected, .console)
        XCTAssertEqual(layout.groups[.left]?.panels, [.profiler])
        XCTAssertEqual(DockPanel.allCases.count, 4)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(layout), as: UTF8.self).contains("\"log\""))
    }

    func testLegacyLogOnlyWindowBecomesConsoleWindow() throws {
        let data = Data(
            #"""
            {
                "groups": [
                    "bottom", {"panels": ["profiler", "frame"], "selected": "frame"}
                ],
                "floating": ["log", {"x": 100, "y": 100, "width": 900, "height": 480}],
                "diagnosticsHidden": false
            }
            """#.utf8)
        let layout = try JSONDecoder().decode(DockLayout.self, from: data).validated()

        XCTAssertEqual(layout.floating[.console], windowFrame)
        XCTAssertNil(layout.region(of: .console))
        XCTAssertEqual(layout.groups[.bottom]?.selected, .frame)
    }

    func testLegacyConsolePlacementWinsOverSeparateLogWindow() throws {
        let data = Data(
            #"""
            {
                "groups": [
                    "right", {"panels": ["console", "settings"], "selected": "console"}
                ],
                "floating": ["log", {"x": 100, "y": 100, "width": 900, "height": 480}],
                "diagnosticsHidden": true
            }
            """#.utf8)
        let layout = try JSONDecoder().decode(DockLayout.self, from: data).validated()

        XCTAssertEqual(layout.groups[.right]?.panels, [.console, .settings])
        XCTAssertTrue(layout.floating.isEmpty)
        XCTAssertTrue(layout.diagnosticsHidden)
    }
}

@MainActor final class DockWindowTests: XCTestCase {
    func testDockDividersResizePanesWithoutStretchingHeaders() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 GPU required for EngineSession")
        }

        _ = NSApplication.shared
        let name = "GraphicsEngine.DockResizeTests.\(UUID().uuidString)"
        let session = try EngineSession(
            defaultsData: JSONEncoder().encode(EngineConfiguration()), settingsName: name, systems: [])
        session.simulationPaused = true
        let host = NSHostingView(rootView: EngineView(session: session))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)

        defer {
            session.diagnosticsDock?.shutdown()
            session.shutdown()
            window.contentView = nil
            window.close()
            let key = "\(name).Dock.v1"
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames " + key + ".horizontal")
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames " + key + ".vertical")

            if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
            {
                try? FileManager.default.removeItem(at: support.appending(path: name))
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        let workspace = try XCTUnwrap(session.diagnosticsDock?.workspace)
        let toolbarHeight = host.bounds.height - workspace.view.bounds.height
        XCTAssertLessThan(toolbarHeight, 60)

        func assertSizesSurviveUpdates(_ panes: [NSView], file: StaticString = #filePath, line: UInt = #line)
        {
            let sizes = panes.map(\.frame.size)

            for _ in 0..<3 {
                session.refreshDiagnostics()
                workspace.updateLayout()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

                for (pane, size) in zip(panes, sizes) {
                    XCTAssertEqual(pane.frame.width, size.width, accuracy: 1, file: file, line: line)
                    XCTAssertEqual(pane.frame.height, size.height, accuracy: 1, file: file, line: line)
                }
            }
        }

        func consoleTab(in view: NSView) -> DockTabButton? {
            if let tab = view as? DockTabButton, tab.panel == .console {
                return tab
            }

            return view.subviews.lazy.compactMap { consoleTab(in: $0) }.first
        }

        let tab = try XCTUnwrap(consoleTab(in: workspace.view))
        let bottom = try XCTUnwrap(workspace.splitViewItems.last).viewController.view
        let tabInset = bottom.bounds.maxY - tab.convert(tab.bounds, to: bottom).maxY

        for height in [800.0, 640.0, 1000.0] {
            window.setContentSize(NSSize(width: 1200, height: height))
            var bottomHeights: [CGFloat] = []

            for topHeight in [260.0, 350.0, 500.0, 280.0] {
                workspace.splitView.setPosition(topHeight, ofDividerAt: 0)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                XCTAssertEqual(
                    host.bounds.height - workspace.view.bounds.height, toolbarHeight, accuracy: 1,
                    "Moving the dock divider must resize the viewport instead of the toolbar")
                let tabFrame = tab.convert(tab.bounds, to: bottom)
                XCTAssertEqual(
                    bottom.bounds.maxY - tabFrame.maxY, tabInset, accuracy: 1,
                    "The dock tab strip must not stretch when the bottom panel grows")
                bottomHeights.append(bottom.bounds.height)
                assertSizesSurviveUpdates([bottom])
            }

            XCTAssertGreaterThan(
                (bottomHeights.max() ?? 0) - (bottomHeights.min() ?? 0), 50,
                "The bottom dock must actually resize when its divider moves")
        }

        workspace.splitView.setPosition(workspace.splitView.bounds.height, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertFalse(try XCTUnwrap(workspace.splitViewItems.last).isCollapsed)
        XCTAssertEqual(bottom.frame.height, 220, accuracy: 1)
        assertSizesSurviveUpdates([bottom])

        let dock = try XCTUnwrap(session.diagnosticsDock)
        dock.dock(.profiler, in: .left)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let horizontal = try XCTUnwrap(workspace.children.first as? NSSplitViewController)

        for (divider, positions) in [(1, [850.0, 930.0, 870.0]), (0, [280.0, 400.0, 300.0])] {
            let item = horizontal.splitViewItems[divider == 0 ? 0 : 2]
            var widths: [CGFloat] = []

            for position in positions {
                horizontal.splitView.setPosition(position, ofDividerAt: divider)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                widths.append(item.viewController.view.bounds.width)
                assertSizesSurviveUpdates(horizontal.splitViewItems.map { $0.viewController.view })
            }

            XCTAssertGreaterThan(
                (widths.max() ?? 0) - (widths.min() ?? 0), 50,
                "Both side docks must actually resize when their dividers move")

            horizontal.splitView.setPosition(
                divider == 0 ? 0 : horizontal.splitView.bounds.width, ofDividerAt: divider)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertFalse(item.isCollapsed)
            XCTAssertEqual(item.viewController.view.frame.width, 280, accuracy: 1)
            assertSizesSurviveUpdates(horizontal.splitViewItems.map { $0.viewController.view })
        }

        dock.toggleDiagnostics()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertTrue(try XCTUnwrap(workspace.splitViewItems.last).isCollapsed)
        XCTAssertTrue(horizontal.splitViewItems[0].isCollapsed)
        XCTAssertFalse(horizontal.splitViewItems[2].isCollapsed)

        dock.toggleDiagnostics()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertFalse(try XCTUnwrap(workspace.splitViewItems.last).isCollapsed)
        XCTAssertFalse(horizontal.splitViewItems[0].isCollapsed)
        assertSizesSurviveUpdates([bottom] + horizontal.splitViewItems.map { $0.viewController.view })
    }

    func testFloatingWindowRetainsContentAndOutgoingMountCannotStealIt() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 GPU required for EngineSession")
        }

        _ = NSApplication.shared
        let name = "GraphicsEngine.DockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let session = try EngineSession(
            defaultsData: JSONEncoder().encode(EngineConfiguration()),
            settingsName: name, systems: [])
        let dock = DiagnosticsDock(session: session, defaults: defaults)

        defer {
            dock.shutdown()
            session.shutdown()
            defaults.removePersistentDomain(forName: name)

            if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
            {
                try? FileManager.default.removeItem(at: support.appending(path: name))
            }
        }

        let original = dock.content(for: .console)
        dock.viewState.console.input = "echo preserved draft"
        dock.viewState.console.search = "Metal"
        dock.viewState.profiler.selectedFrameID = 42
        let outgoing = PanelContainer(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        XCTAssertTrue(dock.mount(.console, in: outgoing, region: .bottom))
        dock.detach(.console)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        XCTAssertTrue(
            original.window === dock.windows[.console], "The detached window must contain the tool host")
        XCTAssertFalse(dock.mount(.console, in: outgoing, region: .bottom))
        XCTAssertTrue(original.window === dock.windows[.console])
        dock.dock(.console, in: .left)
        let incoming = PanelContainer()
        XCTAssertTrue(dock.mount(.console, in: incoming, region: .left))
        XCTAssertTrue(dock.content(for: .console) === original)
        XCTAssertTrue(original.superview === incoming)
        XCTAssertNil(dock.windows[.console])
        XCTAssertEqual(dock.viewState.console.input, "echo preserved draft")
        XCTAssertEqual(dock.viewState.console.search, "Metal")
        XCTAssertEqual(dock.viewState.profiler.selectedFrameID, 42)

        // The native close button must return a floating tool without closing the engine session.
        dock.detach(.profiler)
        let window = try XCTUnwrap(dock.windows[.profiler])
        XCTAssertFalse(dock.windowShouldClose(window))
        XCTAssertNil(dock.windows[.profiler])
        XCTAssertEqual(dock.layout.region(of: .profiler), .bottom)

        let beforeCancel = dock.layout
        dock.beginDrag(.console, source: DockTabButton())
        XCTAssertEqual(dock.dragging, .console)
        dock.cancelDrag()
        XCTAssertNil(dock.dragging)
        XCTAssertEqual(dock.layout, beforeCancel)

        dock.detach(.profiler)
        dock.shutdown()
        let restored = DiagnosticsDock(session: session, defaults: defaults)

        defer {
            restored.shutdown()
        }

        XCTAssertNotNil(restored.layout.floating[.profiler])
        restored.restoreWindows()
        XCTAssertNotNil(restored.windows[.profiler])
    }
}
