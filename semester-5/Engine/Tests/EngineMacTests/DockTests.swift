import XCTest
import AppKit
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
