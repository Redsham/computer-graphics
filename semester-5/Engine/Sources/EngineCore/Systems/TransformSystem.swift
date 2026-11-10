import Foundation
import simd

@MainActor public final class TransformSystem: EngineSystem {
    public init() {}

    public func update(world: World, frame: FrameContext) {
        for entity in world.entities(with: Transform.self) {
            guard let transform = world.get(Transform.self, for: entity) else {
                continue
            }

            if world.get(WorldTransform.self, for: entity) != nil {
                world.set(WorldTransform(transform.matrix), for: entity)
            } else {
                world.deferMutation { $0.set(WorldTransform(transform.matrix), for: entity) }
            }
        }
    }
}
