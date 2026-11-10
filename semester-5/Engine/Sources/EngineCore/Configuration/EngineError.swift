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
