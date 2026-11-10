import Foundation

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
