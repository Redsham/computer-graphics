import AppKit
import Charts
import EngineCore
import EngineMetal
import SwiftUI

// MARK: - Toolbar and tabs

@MainActor struct DiagnosticsToolbar: View {
    @ObservedObject var session: EngineSession

    var body: some View {
        HStack(spacing: 12) {
            Button {
                session.togglePause()
            } label: {
                Label(
                    session.simulationPaused ? "Resume" : "Pause",
                    systemImage: session.simulationPaused ? "play.fill" : "pause.fill")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button {
                session.stepFrame()
            } label: {
                Label("Step", systemImage: "forward.frame")
            }

            Button {
                session.captureFrame()
            } label: {
                Label("Capture frame", systemImage: "camera")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Xcode GPU trace…") {
                session.exportGPUTrace()
            }

            Spacer()

            if session.simulationPaused {
                Text("PAUSED")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.orange)
            }

            Button {
                session.diagnosticsVisible.toggle()
            } label: {
                Label("Diagnostics", systemImage: "terminal")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

@MainActor struct DiagnosticsPanel: View {
    @ObservedObject var session: EngineSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Diagnostics", selection: $session.diagnosticsTab) {
                    ForEach(["Console", "Log", "Profiler", "Frame"], id: \.self) {
                        Text($0)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)

                Spacer()

                Text(session.log.fileURL?.lastPathComponent ?? "Memory log")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Export log…") {
                    session.exportLog()
                }

                Button("Clear log") {
                    session.log.clear()

                    session.refreshDiagnostics()
                }
            }
            .padding(10)

            Divider()

            switch session.diagnosticsTab {
            case "Console":
                ConsolePanel(session: session)
            case "Log":
                LogPanel(session: session)
            case "Profiler":
                ProfilerPanel(session: session)
            default:
                FrameDebuggerPanel(session: session)
            }
        }
        .background(.background)
    }
}

// MARK: - Console

@MainActor private struct ConsolePanel: View {
    @ObservedObject var session: EngineSession
    @State private var input = ""
    @State private var historyIndex: Int?
    @State private var suggestions = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            LogRows(entries: session.logEntries, follow: true)

            Divider()

            if !suggestions.isEmpty {
                Text(suggestions)
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

                TextField("help · command history ↑/↓ · complete Tab", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                    .onSubmit {
                        session.executeCommand(input)
                        input = ""
                        suggestions = ""
                        historyIndex = nil
                    }
                    .onKeyPress(.upArrow) {
                        let history = session.commands.history

                        guard !history.isEmpty else {
                            return .handled
                        }

                        let index = max(0, (historyIndex ?? history.count) - 1)
                        historyIndex = index
                        input = history[index]
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        let history = session.commands.history
                        let index = min(history.count, (historyIndex ?? history.count) + 1)
                        historyIndex = index
                        input = index < history.count ? history[index] : ""
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        let matches = session.commands.completions(input)

                        if matches.count == 1 {
                            input = matches[0] + " "
                            suggestions = ""
                        } else {
                            suggestions = matches.joined(separator: "  ")
                        }

                        return .handled
                    }

                Button("Run") {
                    session.executeCommand(input)
                    input = ""
                    historyIndex = nil
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Log viewer

@MainActor private struct LogPanel: View {
    @ObservedObject var session: EngineSession
    @State private var search = ""
    @State private var minimum = LogLevel.debug
    @State private var follow = true
    @State private var frozen: [LogEntry]?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search category or message", text: $search)
                    .textFieldStyle(.roundedBorder)

                Picker("Minimum", selection: $minimum) {
                    ForEach(LogLevel.allCases, id: \.self) {
                        Text($0.rawValue)
                            .tag($0)
                    }
                }
                .frame(width: 180)

                Toggle("Follow", isOn: $follow)

                Button(frozen == nil ? "Freeze display" : "Live display") {
                    frozen = frozen == nil ? session.logEntries : nil
                }
            }
            .padding(8)

            LogRows(
                entries: (frozen ?? session.logEntries).filter {
                    $0.level.rank >= minimum.rank
                        && (search.isEmpty
                            || "\($0.category) \($0.message)".localizedCaseInsensitiveContains(search))
                }, follow: follow)
        }
    }
}

@MainActor private struct LogRows: View {
    let entries: [LogEntry]
    let follow: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(
                                entry.timestamp,
                                format: .dateTime.hour().minute().second().secondFraction(.fractional(3))
                            )
                            .foregroundStyle(.secondary)

                            Text(entry.level.rawValue.uppercased())
                                .frame(width: 64, alignment: .leading)
                                .foregroundStyle(color(entry.level))

                            Text("[\(entry.category)]")
                                .foregroundStyle(.secondary)

                            Text(entry.message)
                                .foregroundStyle(color(entry.level))
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .id(entry.id)
                    }

                    Color.clear.frame(height: 1)
                        .id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .onChange(of: entries.last?.id) {
                if follow {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
    }

    private func color(_ level: LogLevel) -> Color {
        switch level {
        case .debug:
            .secondary
        case .info:
            .primary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

// MARK: - Profiler

@MainActor private struct ProfilerPanel: View {
    @ObservedObject var session: EngineSession
    @State private var frozen: [FrameProfile]?
    @State private var selectedFrameID: UInt64?

    private var frames: [FrameProfile] {
        frozen ?? session.profileFrames
    }

    private var latest: FrameProfile? {
        frames.first(where: {
            $0.id == selectedFrameID
        }) ?? frames.last(where: {
            $0.gpuMilliseconds != nil
        }) ?? frames.last
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(frozen == nil ? "Freeze profiler" : "Live profiler") {
                        frozen = frozen == nil ? session.profileFrames : nil
                    }

                    Button("Export…") {
                        session.exportProfiles(frames)
                    }

                    Button("Clear") {
                        session.renderer.profiles.clear()

                        session.refreshDiagnostics()
                    }

                    Toggle(
                        "GPU timestamps",
                        isOn: Binding(
                            get: {
                                session.renderer.profilingEnabled
                            },
                            set: {
                                session.renderer.profilingEnabled = $0
                            }))
                }

                Chart(frames) { frame in
                    LineMark(x: .value("Frame", frame.id), y: .value("Milliseconds", frame.cpuMilliseconds))
                        .foregroundStyle(by: .value("Stage", "CPU"))

                    if let gpu = frame.gpuMilliseconds {
                        LineMark(x: .value("Frame", frame.id), y: .value("Milliseconds", gpu))
                            .foregroundStyle(by: .value("Stage", "GPU"))
                    }
                }
                .chartXSelection(value: $selectedFrameID)
                .chartYAxisLabel("ms")
                .chartLegend(position: .bottom)
                .frame(minHeight: 115)

                let values = frames.map(\.cpuMilliseconds).sorted()

                Text(
                    String(
                        format: "CPU avg %.3f ms · p95 %.3f ms · max %.3f ms · %d frames",
                        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count),
                        values.isEmpty ? 0 : values[Int(Double(values.count - 1) * 0.95)], values.last ?? 0,
                        values.count)
                )
                .font(.caption.monospaced())

                if let latest {
                    Text(
                        String(
                            format: "GPU wait %.3f ms · %d draws · %.2f MiB frame residency",
                            latest.waitMilliseconds,
                            latest.drawCount, Double(latest.resourceBytes) / 1_048_576)
                    )
                    .font(.caption.monospaced())

                    if latest.instrumented {
                        Text("Captured frame includes readback/instrumentation overhead.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frame \(latest?.id ?? 0)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text("CPU systems")
                        .font(.headline)

                    ForEach(latest?.systems ?? []) { timing in
                        row(timing)
                    }

                    Divider()

                    Text("CPU encoding / GPU passes")
                        .font(.headline)

                    ForEach(latest?.passesCPU ?? []) { timing in
                        row(timing)

                        if let gpu = latest?.passesGPU.first(where: {
                            $0.name == timing.name
                        }) {
                            Text(String(format: "GPU %.3f ms", gpu.milliseconds))
                                .font(.caption.monospaced())
                                .foregroundStyle(.mint)
                        }
                    }

                    if latest?.gpuMilliseconds == nil {
                        Text("GPU result pending or counters disabled.")
                            .font(.caption)
                            .foregroundStyle(
                                .secondary)
                    }
                }
            }
            .frame(width: 310)
        }
        .padding(12)
    }

    private func row(_ sample: TimingSample) -> some View {
        HStack {
            Text(sample.name)

            Spacer()

            Text(String(format: "%.3f ms", sample.milliseconds))
                .monospacedDigit()
        }
        .font(.caption)
    }
}
