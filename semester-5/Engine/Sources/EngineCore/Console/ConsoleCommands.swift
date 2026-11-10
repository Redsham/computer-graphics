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
