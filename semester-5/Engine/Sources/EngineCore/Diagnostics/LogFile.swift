import Foundation

// MARK: - File output

/// The file queue owns every mutable disk state; UI logging never blocks on disk I/O.
final class LogFile: @unchecked Sendable {
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
