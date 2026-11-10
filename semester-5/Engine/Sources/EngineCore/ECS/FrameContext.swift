// MARK: - Frame context

@MainActor public final class FrameContext {
    public var deltaTime: Float = 0
    public var aspectRatio: Float = 1
    public var input = InputSnapshot()
    public var configuration = EngineConfiguration()
    public var snapshot = RenderSnapshot()

    public init() {}
}
