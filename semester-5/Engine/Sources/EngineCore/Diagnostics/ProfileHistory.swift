import Foundation

@MainActor public final class ProfileHistory {
    public var frames: [FrameProfile] {
        Array(history)
    }
    public private(set) var revision: UInt64 = 0
    private var history: BoundedHistory<FrameProfile>
    public let capacity: Int

    public init(capacity: Int = 300) {
        self.capacity = max(1, capacity)
        history = BoundedHistory(capacity: self.capacity)
    }

    public func append(_ frame: FrameProfile) {
        history.append(frame)
        revision &+= 1
    }

    public func updateGPU(frameID: UInt64, total: Double?, passes: [TimingSample]) {
        guard let index = history.firstIndex(where: { $0.id == frameID }) else {
            return
        }

        history[index].gpuMilliseconds = total

        if !passes.isEmpty {
            history[index].passesGPU = passes
        }

        revision &+= 1
    }

    public func updateCPU(frameID: UInt64, total: Double, systems: [TimingSample]) {
        guard let index = history.firstIndex(where: { $0.id == frameID }) else {
            return
        }

        history[index].cpuMilliseconds = total
        history[index].systems = systems
        revision &+= 1
    }

    public func clear() {
        history.removeAll()
        revision &+= 1
    }

    public func percentile(_ fraction: Double) -> Double {
        let values = history.map(\.cpuMilliseconds).sorted()

        guard !values.isEmpty else {
            return 0
        }

        return values[Int((Double(values.count - 1) * min(max(fraction, 0), 1)).rounded())]
    }
}
