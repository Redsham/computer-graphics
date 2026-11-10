import Foundation

/// Bundle defaults are authoritative; invalid user data never partially applies.
public struct ConfigurationStore: Sendable {
    public let defaults: EngineConfiguration
    public let userURL: URL

    public init(defaultsData: Data, userURL: URL) throws {
        defaults = try JSONDecoder().decode(EngineConfiguration.self, from: defaultsData).validated()
        self.userURL = userURL
    }

    public func load() -> (configuration: EngineConfiguration, warning: String?) {
        guard FileManager.default.fileExists(atPath: userURL.path) else {
            return (defaults, nil)
        }

        do {
            return (
                try JSONDecoder().decode(EngineConfiguration.self, from: Data(contentsOf: userURL))
                    .validated(), nil
            )
        } catch {
            return (defaults, "User settings could not be loaded: \(error.localizedDescription)")
        }
    }

    public func save(_ configuration: EngineConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration.validated())
        try FileManager.default.createDirectory(
            at: userURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: userURL, options: .atomic)
    }
}
