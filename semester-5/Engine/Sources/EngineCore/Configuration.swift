import Foundation

public enum EngineError: Error, LocalizedError, Sendable {
  case invalidConfiguration(String)
  case unavailable(String)
  case invalidPipeline(String)
  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message), .unavailable(let message),
      .invalidPipeline(let message):
      message
    }
  }
}

public struct EngineConfiguration: Codable, Equatable, Sendable {
  public var targetFPS = 60
  public var sampleCount = 1
  public var wireframe = false
  public var background = SIMD3<Float>(0.025, 0.035, 0.055)
  public var exposure: Float = 1
  public var fieldOfView: Float = 60
  public var cameraSpeed: Float = 3
  public init() {}
  public func validated() throws -> Self {
    guard (1...240).contains(targetFPS), [1, 4].contains(sampleCount),
      exposure.isFinite, (0.1...8).contains(exposure),
      fieldOfView.isFinite, (20...110).contains(fieldOfView),
      cameraSpeed.isFinite, (0.1...20).contains(cameraSpeed),
      (0..<3).allSatisfy({ background[$0].isFinite && (0...1).contains(background[$0]) })
    else {
      throw EngineError.invalidConfiguration(
        "Invalid engine configuration: FPS 1–240, MSAA 1/4, exposure 0.1–8, FOV 20–110, speed 0.1–20, RGB 0–1 required."
      )
    }
    return self
  }
}

/// Bundle defaults are authoritative; invalid user data never partially applies.
public struct ConfigurationStore: Sendable {
  public let defaults: EngineConfiguration
  public let userURL: URL
  public init(defaultsData: Data, userURL: URL) throws {
    defaults = try JSONDecoder().decode(EngineConfiguration.self, from: defaultsData).validated()
    self.userURL = userURL
  }
  public func load() -> (configuration: EngineConfiguration, warning: String?) {
    guard FileManager.default.fileExists(atPath: userURL.path) else { return (defaults, nil) }
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
