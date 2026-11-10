import Foundation

// MARK: - Panel identity and placement

enum DockPanel: String, CaseIterable, Codable, Identifiable {
    case console, profiler, frame, settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .console:
            "Console"
        case .profiler:
            "Profiler"
        case .frame:
            "Frame Debugger"
        case .settings:
            "Renderer"
        }
    }

    var symbol: String {
        switch self {
        case .console:
            "terminal"
        case .profiler:
            "chart.xyaxis.line"
        case .frame:
            "square.stack.3d.up"
        case .settings:
            "slider.horizontal.3"
        }
    }
}

enum DockRegion: String, CaseIterable, Codable {
    case left, right, bottom
}

struct DockGroup: Codable, Equatable {
    var panels: [DockPanel] = []
    var selected: DockPanel?
}

struct DockWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width >= 400 && height >= 240
            && width <= 16_384 && height <= 16_384
    }
}

// MARK: - Layout transitions

struct DockLayout: Codable, Equatable {
    var groups: [DockRegion: DockGroup]
    var floating: [DockPanel: DockWindowFrame] = [:]
    var diagnosticsHidden = false

    static let initial = DockLayout(groups: [
        .left: DockGroup(),
        .right: DockGroup(panels: [.settings], selected: .settings),
        .bottom: DockGroup(panels: [.console, .profiler, .frame], selected: .console),
    ])

    func region(of panel: DockPanel) -> DockRegion? {
        DockRegion.allCases.first { groups[$0]?.panels.contains(panel) == true }
    }

    func isVisible(_ panel: DockPanel) -> Bool {
        (floating[panel] != nil || DockRegion.allCases.contains { selection(in: $0) == panel })
            && (!diagnosticsHidden || panel == .settings)
    }

    func visiblePanels(in region: DockRegion) -> [DockPanel] {
        (groups[region]?.panels ?? []).filter { !diagnosticsHidden || $0 == .settings }
    }

    func selection(in region: DockRegion) -> DockPanel? {
        let panels = visiblePanels(in: region)
        return panels.first(where: { $0 == groups[region]?.selected }) ?? panels.first
    }

    mutating func remove(_ panel: DockPanel) {
        for region in DockRegion.allCases {
            var group = groups[region] ?? DockGroup()
            group.panels.removeAll { $0 == panel }

            if group.selected == panel {
                group.selected = group.panels.first
            }

            groups[region] = group
        }

        floating.removeValue(forKey: panel)
    }

    mutating func dock(_ panel: DockPanel, in region: DockRegion, before target: DockPanel? = nil) {
        guard target != panel else {
            return
        }

        remove(panel)
        var group = groups[region] ?? DockGroup()
        let index = target.flatMap { group.panels.firstIndex(of: $0) } ?? group.panels.endIndex
        group.panels.insert(panel, at: index)
        group.selected = panel
        groups[region] = group
        diagnosticsHidden = false
    }

    mutating func detach(_ panel: DockPanel, frame: DockWindowFrame) {
        remove(panel)
        floating[panel] = frame
    }

    /// Reject broken saved state rather than allowing duplicate ownership of a panel view.
    func validated() throws -> Self {
        var seen: Set<DockPanel> = []

        for region in DockRegion.allCases {
            let group = groups[region] ?? DockGroup()

            guard group.selected.map(group.panels.contains) ?? group.panels.isEmpty else {
                throw CocoaError(.coderReadCorrupt)
            }

            for panel in group.panels {
                guard seen.insert(panel).inserted else {
                    throw CocoaError(.coderReadCorrupt)
                }
            }
        }

        for (panel, frame) in floating {
            guard seen.insert(panel).inserted, frame.isValid else {
                throw CocoaError(.coderReadCorrupt)
            }
        }

        return self
    }
}

// MARK: - Compatibility with separate Console and Log panels

extension DockLayout {
    private enum CodingKeys: String, CodingKey {
        case groups, floating, diagnosticsHidden
    }

    private enum SavedPanel: String, Codable {
        case console, log, profiler, frame, settings
    }

    private struct SavedGroup: Decodable {
        let panels: [SavedPanel]
        let selected: SavedPanel?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let savedGroups = try container.decode([DockRegion: SavedGroup].self, forKey: .groups)
        let savedWindows = try container.decode([SavedPanel: DockWindowFrame].self, forKey: .floating)
        diagnosticsHidden = try container.decode(Bool.self, forKey: .diagnosticsHidden)
        var seen: Set<SavedPanel> = []

        // Validate before merging, so migration cannot conceal corrupted ownership or selection.
        for group in savedGroups.values {
            guard group.selected.map(group.panels.contains) ?? group.panels.isEmpty else {
                throw CocoaError(.coderReadCorrupt)
            }

            for panel in group.panels {
                guard seen.insert(panel).inserted else {
                    throw CocoaError(.coderReadCorrupt)
                }
            }
        }

        for (panel, frame) in savedWindows {
            guard seen.insert(panel).inserted, frame.isValid else {
                throw CocoaError(.coderReadCorrupt)
            }
        }

        // Prefer Console's placement. If it was hidden, reuse Log's dock or floating window.
        let hasConsole = seen.contains(.console)

        func merged(_ panel: SavedPanel) -> DockPanel? {
            if panel == .log {
                return hasConsole ? nil : .console
            }

            return DockPanel(rawValue: panel.rawValue)
        }

        groups = savedGroups.mapValues { group in
            let panels = group.panels.compactMap(merged)
            let selected =
                group.selected == .log && panels.contains(.console)
                ? .console : group.selected.flatMap(merged)
            return DockGroup(panels: panels, selected: selected ?? panels.first)
        }
        floating = Dictionary(
            uniqueKeysWithValues: savedWindows.compactMap { panel, frame in
                merged(panel).map { ($0, frame) }
            })
    }
}
