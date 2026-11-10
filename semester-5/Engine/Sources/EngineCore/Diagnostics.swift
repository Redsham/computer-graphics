import Foundation
import os

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

// MARK: - File output

/// The file queue owns every mutable disk state; UI logging never blocks on disk I/O.
private final class LogFile: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "GraphicsEngine.LogFile", qos: .utility)
    private let limit: Int
    private var handle: FileHandle?
    private var size = 0
    private var failure: String?
    var onFailure: (@Sendable (String) -> Void)?

    init(url: URL, limit: Int) throws {
        self.url = url
        self.limit = limit
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try open()
    }

    private func open() throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        handle = try FileHandle(forWritingTo: url)
        size = Int(try handle?.seekToEnd() ?? 0)
    }

    func append(_ entry: LogEntry) {
        queue.async { [self] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                var data = try encoder.encode(entry)
                data.append(10)

                if size + data.count > limit {
                    try handle?.close()
                    handle = nil

                    for index in stride(from: 2, through: 0, by: -1) {
                        let source = index == 0 ? url : url.appendingPathExtension("\(index)")
                        let destination = url.appendingPathExtension("\(index + 1)")

                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }

                        if FileManager.default.fileExists(atPath: source.path) {
                            try FileManager.default.moveItem(at: source, to: destination)
                        }
                    }

                    try open()
                }

                try handle?.write(contentsOf: data)
                size += data.count
            } catch {
                if failure == nil {
                    failure = error.localizedDescription
                    onFailure?(error.localizedDescription)
                }
            }
        }
    }

    func flush() -> String? {
        queue.sync {
            do {
                try handle?.synchronize()
            } catch {
                failure = error.localizedDescription
            }

            return failure
        }
    }

    deinit {
        try? handle?.close()
    }
}

// MARK: - Logging API

@MainActor public final class EngineLog {
    public private(set) var entries: [LogEntry] = []
    public private(set) var revision: UInt64 = 0
    public let capacity: Int
    public let fileURL: URL?
    private let file: LogFile?
    private var nextID: UInt64 = 0
    private let system = Logger(subsystem: "GraphicsEngine", category: "Engine")

    public init(capacity: Int = 5000, fileURL: URL? = nil, fileLimit: Int = 4 * 1024 * 1024) throws {
        self.capacity = max(1, capacity)
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
        entries.append(entry)

        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }

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
        entries.removeAll(keepingCapacity: true)
        revision &+= 1
    }

    public func filtered(minimum: LogLevel = .debug, search: String = "") -> [LogEntry] {
        entries.filter {
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

// MARK: - Profiling

public struct TimingSample: Identifiable, Codable, Sendable {
    public var id: String {
        name
    }

    public let name: String
    public let milliseconds: Double

    public init(_ name: String, milliseconds: Double) {
        self.name = name
        self.milliseconds = milliseconds
    }
}

public struct FrameProfile: Identifiable, Codable, Sendable {
    public let id: UInt64
    public var cpuMilliseconds: Double
    public var gpuMilliseconds: Double?
    public var waitMilliseconds: Double
    public var systems: [TimingSample]
    public var passesCPU: [TimingSample]
    public var passesGPU: [TimingSample]
    public var drawCount: Int
    public var objectCount: Int
    public var resourceBytes: Int
    public var instrumented: Bool

    public init(
        id: UInt64, cpuMilliseconds: Double = 0, gpuMilliseconds: Double? = nil,
        waitMilliseconds: Double = 0, systems: [TimingSample] = [], passesCPU: [TimingSample] = [],
        passesGPU: [TimingSample] = [], drawCount: Int = 0, objectCount: Int = 0,
        resourceBytes: Int = 0, instrumented: Bool = false
    ) {
        self.id = id
        self.cpuMilliseconds = cpuMilliseconds
        self.gpuMilliseconds = gpuMilliseconds
        self.waitMilliseconds = waitMilliseconds
        self.systems = systems
        self.passesCPU = passesCPU
        self.passesGPU = passesGPU
        self.drawCount = drawCount
        self.objectCount = objectCount
        self.resourceBytes = resourceBytes
        self.instrumented = instrumented
    }
}

@MainActor public final class ProfileHistory {
    public private(set) var frames: [FrameProfile] = []
    public let capacity: Int

    public init(capacity: Int = 300) {
        self.capacity = max(1, capacity)
    }

    public func append(_ frame: FrameProfile) {
        frames.append(frame)

        if frames.count > capacity {
            frames.removeFirst(frames.count - capacity)
        }
    }

    public func updateGPU(frameID: UInt64, total: Double?, passes: [TimingSample]) {
        guard let index = frames.firstIndex(where: { $0.id == frameID }) else {
            return
        }

        frames[index].gpuMilliseconds = total

        if !passes.isEmpty {
            frames[index].passesGPU = passes
        }
    }

    public func updateCPU(frameID: UInt64, total: Double, systems: [TimingSample]) {
        guard let index = frames.firstIndex(where: { $0.id == frameID }) else {
            return
        }

        frames[index].cpuMilliseconds = total
        frames[index].systems = systems
    }

    public func clear() {
        frames.removeAll(keepingCapacity: true)
    }

    public func percentile(_ fraction: Double) -> Double {
        let values = frames.map(\.cpuMilliseconds).sorted()

        guard !values.isEmpty else {
            return 0
        }

        return values[Int((Double(values.count - 1) * min(max(fraction, 0), 1)).rounded())]
    }
}

// MARK: - Console parsing

public enum ConsoleParser {
    public static func tokenize(_ input: String) throws -> [String] {
        var words: [String] = []
        var word = ""
        var quote: Character?
        var escaping = false
        var started = false

        for character in input {
            if escaping {
                word.append(character)
                escaping = false
                started = true
            } else if character == "\\" {
                escaping = true
                started = true
            } else if let current = quote {
                if character == current {
                    quote = nil
                } else {
                    word.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started {
                    words.append(word)
                    word = ""
                    started = false
                }
            } else {
                word.append(character)
                started = true
            }
        }

        guard quote == nil, !escaping else {
            throw EngineError.invalidConfiguration("Unclosed quote or escape in command.")
        }

        if started {
            words.append(word)
        }

        return words
    }
}

// MARK: - Command registry

@MainActor public final class ConsoleCommands {
    public struct Command {
        public let name: String
        public let help: String
        let run: @MainActor ([String]) throws -> String
    }

    public private(set) var history: [String] = []

    public var names: [String] {
        commands.keys.sorted()
    }

    private var commands: [String: Command] = [:]

    public init() {}

    public func register(
        _ name: String, help: String, run: @escaping @MainActor ([String]) throws -> String
    ) {
        commands[name] = Command(name: name, help: help, run: run)
    }

    public func completions(_ prefix: String) -> [String] {
        names.filter { $0.hasPrefix(prefix) }
    }

    public var help: String {
        names.compactMap { commands[$0] }.map { "\($0.name) — \($0.help)" }.joined(separator: "\n")
    }

    public func execute(_ input: String) throws -> String {
        let words = try ConsoleParser.tokenize(input)

        guard let name = words.first else {
            return ""
        }

        if history.last != input {
            history.append(input)
        }

        if history.count > 200 {
            history.removeFirst()
        }

        guard let command = commands[name] else {
            throw EngineError.invalidConfiguration("Unknown command '\(name)'. Use help.")
        }

        return try command.run(Array(words.dropFirst()))
    }
}

// MARK: - Binary decoding

/// IEEE 754 half decoding without Float16, which is unavailable in Intel package slices.
public enum BinaryScalar {
    public static func float16(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = Int((bits >> 10) & 31)
        var mantissa = UInt32(bits & 1023)

        if exponent == 31 {
            return Float(bitPattern: sign | 0x7f80_0000 | (mantissa << 13))
        }

        if exponent == 0 {
            if mantissa == 0 {
                return Float(bitPattern: sign)
            }

            var unbiased = -14

            while mantissa & 1024 == 0 {
                mantissa <<= 1
                unbiased -= 1
            }

            return Float(bitPattern: sign | (UInt32(unbiased + 127) << 23) | ((mantissa & 1023) << 13))
        }

        return Float(bitPattern: sign | (UInt32(exponent + 112) << 23) | (mantissa << 13))
    }
}
