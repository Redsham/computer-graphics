import Foundation
import os

// MARK: - Logging API

@MainActor public final class EngineLog {
    public var entries: [LogEntry] {
        Array(history)
    }
    private var history: BoundedHistory<LogEntry>
    public private(set) var revision: UInt64 = 0
    public let capacity: Int
    public let fileURL: URL?
    private let file: LogFile?
    private var nextID: UInt64 = 0
    private let system = Logger(subsystem: "GraphicsEngine", category: "Engine")

    public init(capacity: Int = 5000, fileURL: URL? = nil, fileLimit: Int = 4 * 1024 * 1024) throws {
        self.capacity = max(1, capacity)
        history = BoundedHistory(capacity: self.capacity)
        self.fileURL = fileURL
        file = try fileURL.map { try LogFile(url: $0, limit: max(1024, fileLimit)) }
        file?.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.write(
                    .error, category: "LogFile",
                    "Disk logging failed; in-memory journal is still available: \(message)")
            }
        }
    }

    public func write(_ level: LogLevel = .info, category: String, _ message: String) {
        nextID += 1
        let entry = LogEntry(
            id: nextID, timestamp: Date(), level: level, category: category,
            message: String(message.prefix(65536)))
        history.append(entry)

        revision &+= 1
        file?.append(entry)
        let text = "[\(category)] \(entry.message)"

        switch level {
        case .debug:
            system.debug("\(text, privacy: .public)")
        case .info:
            system.info("\(text, privacy: .public)")
        case .warning:
            system.warning("\(text, privacy: .public)")
        case .error:
            system.error("\(text, privacy: .public)")
        }
    }

    public func clear() {
        history.removeAll()
        revision &+= 1
    }

    public func filtered(minimum: LogLevel = .debug, search: String = "") -> [LogEntry] {
        history.filter {
            $0.level.rank >= minimum.rank
                && (search.isEmpty
                    || "\($0.category) \($0.message)".localizedCaseInsensitiveContains(search))
        }
    }

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    public func flush() -> String? {
        file?.flush()
    }
}
