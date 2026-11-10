// MARK: - System lifecycle

@MainActor public protocol EngineSystem: AnyObject {
    func start(world: World)

    func update(world: World, frame: FrameContext)

    func stop(world: World)
}

extension EngineSystem {
    public func start(world: World) {}

    public func stop(world: World) {}
}
