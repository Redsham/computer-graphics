import Foundation

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
