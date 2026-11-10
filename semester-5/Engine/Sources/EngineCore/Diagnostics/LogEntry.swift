import Foundation

// MARK: - Log records

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug, info, warning, error

    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

public struct LogEntry: Identifiable, Codable, Sendable {
    public let id: UInt64
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
}
