import EngineCore
import SwiftUI

// MARK: - Log viewer

@MainActor struct LogRows: View {
    let entries: [LogEntry]
    let follow: Bool

    var body: some View {
        GeometryReader { viewport in
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
                            .fixedSize(horizontal: true, vertical: false)
                            .id(entry.id)
                        }

                        Color.clear.frame(height: 1)
                            .id("end")
                    }
                    .frame(minWidth: max(0, viewport.size.width - 20), alignment: .leading)
                    .padding(10)
                }
                .defaultScrollAnchor(.topLeading)
                .onChange(of: entries.last?.id) {
                    if follow {
                        proxy.scrollTo("end", anchor: .bottomLeading)
                    }
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
