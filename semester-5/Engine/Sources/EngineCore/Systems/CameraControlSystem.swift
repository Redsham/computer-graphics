import Foundation
import simd

@MainActor public final class CameraControlSystem: EngineSystem {
    public init() {}

    public func update(world: World, frame: FrameContext) {
        for entity in world.entities(with: Camera.self) {
            guard var camera = world.get(Camera.self, for: entity),
                var transform = world.get(Transform.self, for: entity)
            else {
                continue
            }

            camera.yaw -= frame.input.look.x * 0.003
            camera.pitch = min(max(camera.pitch - frame.input.look.y * 0.003, -1.5), 1.5)
            transform.rotation =
                simd_quatf(angle: camera.yaw, axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: camera.pitch, axis: SIMD3(1, 0, 0))
            let movement = frame.input.movement

            if simd_length_squared(movement) > 0 {
                transform.position +=
                    transform.rotation.act(simd_normalize(movement)) * frame.configuration.cameraSpeed
                    * frame.deltaTime
            }

            world.set(camera, for: entity)
            world.set(transform, for: entity)
        }
    }
}
