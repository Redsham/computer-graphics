import EngineCore
import SwiftUI

// MARK: - Console

@MainActor struct ConsolePanel: View {
    @ObservedObject var session: EngineSession
    @FocusState private var focused: Bool

    @ObservedObject var state: ConsoleViewState

    var body: some View {
        VStack(spacing: 0) {
            logControls

            Divider()

            LogRows(
                entries: (state.frozen ?? session.logEntries).filter {
                    $0.level.rank >= state.minimum.rank
                        && (state.search.isEmpty
                            || "\($0.category) \($0.message)".localizedCaseInsensitiveContains(state.search))
                }, follow: state.follow)

            Divider()

            if !state.suggestions.isEmpty {
                Text(state.suggestions)
                    .font(.caption.monospaced())
                    .frame(
                        maxWidth: .infinity, alignment: .leading
                    )
                    .padding(.horizontal, 12)
            }

            HStack {
                Text(">")
                    .foregroundStyle(.mint)
                    .font(.system(.body, design: .monospaced))

                TextField("help · command history ↑/↓ · complete Tab", text: $state.input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                    .onSubmit {
                        session.executeCommand(state.input)
                        state.input = ""
                        state.suggestions = ""
                        state.historyIndex = nil
                    }
                    .onKeyPress(.upArrow) {
                        let history = session.commands.history

                        guard !history.isEmpty else {
                            return .handled
                        }

                        let index = max(0, (state.historyIndex ?? history.count) - 1)
                        state.historyIndex = index
                        state.input = history[index]
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        let history = session.commands.history
                        let index = min(history.count, (state.historyIndex ?? history.count) + 1)
                        state.historyIndex = index
                        state.input = index < history.count ? history[index] : ""
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        let matches = session.commands.completions(state.input)

                        if matches.count == 1 {
                            state.input = matches[0] + " "
                            state.suggestions = ""
                        } else {
                            state.suggestions = matches.joined(separator: "  ")
                        }

                        return .handled
                    }

                Button("Run") {
                    session.executeCommand(state.input)
                    state.input = ""
                    state.historyIndex = nil
                }
            }
            .padding(12)
        }
    }

    // MARK: - Journal controls

    private var logControls: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search category or message", text: $state.search)
                    .textFieldStyle(.roundedBorder)

                Picker("Minimum", selection: $state.minimum) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue)
                            .tag(level)
                    }
                }
                .frame(width: 180)
            }

            HStack {
                Toggle("Follow", isOn: $state.follow)

                Button(state.frozen == nil ? "Freeze display" : "Live display") {
                    state.frozen = state.frozen == nil ? session.logEntries : nil
                }

                Spacer()

                Button("Export log…") {
                    session.exportLog()
                }

                Button("Clear log") {
                    session.log.clear()
                    state.frozen = nil
                    session.refreshDiagnostics()
                }
            }
        }
        .padding(8)
    }
}
