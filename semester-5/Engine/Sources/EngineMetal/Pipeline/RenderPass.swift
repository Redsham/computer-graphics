import EngineCore
import Metal

// MARK: - Pass lifecycle

@MainActor public protocol RenderPass: AnyObject {
    func declaration(configuration: EngineConfiguration) -> PassDeclaration

    func prepare(_ context: PassPreparationContext) throws

    func prepareFrame(_ context: PassContext) throws

    func encode(_ context: PassContext) throws
}

extension RenderPass {
    public func prepareFrame(_ context: PassContext) throws {}
}
