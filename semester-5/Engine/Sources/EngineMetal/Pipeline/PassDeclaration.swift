import EngineCore
import Metal

// MARK: - Resource contracts

public struct TextureContract: Equatable, Sendable {
    public let name: String
    public let format: MTLPixelFormat
    public let samples: Int

    public init(_ name: String, format: MTLPixelFormat, samples: Int = 1) {
        self.name = name
        self.format = format
        self.samples = samples
    }
}

public struct PassDeclaration: Sendable {
    public let name: String
    public let inputs: [TextureContract]
    public let outputs: [TextureContract]

    public init(name: String, inputs: [TextureContract] = [], outputs: [TextureContract]) {
        self.name = name
        self.inputs = inputs
        self.outputs = outputs
    }
}
