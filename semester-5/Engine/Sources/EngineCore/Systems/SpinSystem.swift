import Foundation
import simd

@MainActor public final class SpinSystem: EngineSystem {
    public init() {}

    public func update(world: World, frame: FrameContext) {
        for entity in world.entities(with: Spin.self) {
            guard let spin = world.get(Spin.self, for: entity),
                var transform = world.get(Transform.self, for: entity)
            else {
                continue
            }

            transform.rotation = simd_normalize(
                simd_quatf(angle: spin.speed * frame.deltaTime, axis: simd_normalize(SIMD3(0.3, 1, 0)))
                    * transform.rotation)
            world.set(transform, for: entity)
        }
    }
}
