import Foundation

// MARK: - Scheduling

@MainActor public final class SystemScheduler {
    private let systems: [any EngineSystem]
    private let names: [String]
    private var started = false
    public private(set) var lastTimings: [TimingSample] = []

    public init(systems: [any EngineSystem]) {
        self.systems = systems
        names = systems.enumerated().map { "\($0.offset + 1). \(String(describing: type(of: $0.element)))" }
        lastTimings.reserveCapacity(systems.count)
    }

    public func start(world: World) {
        guard !started else {
            return
        }

        started = true

        for system in systems {
            system.start(world: world)
        }
    }

    public func update(world: World, frame: FrameContext) {
        start(world: world)
        world.beginUpdate()
        lastTimings.removeAll(keepingCapacity: true)

        for (index, system) in systems.enumerated() {
            let start = ProcessInfo.processInfo.systemUptime
            system.update(world: world, frame: frame)
            lastTimings.append(
                TimingSample(
                    names[index], milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000))
        }
        world.endUpdate()
    }

    public func stop(world: World) {
        guard started else {
            return
        }

        for system in systems.reversed() {
            system.stop(world: world)
        }

        started = false
    }
}
