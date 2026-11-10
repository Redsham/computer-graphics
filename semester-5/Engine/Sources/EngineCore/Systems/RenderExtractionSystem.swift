import Foundation
import simd

@MainActor public final class RenderExtractionSystem: EngineSystem {
    public init() {}

    public func update(world: World, frame: FrameContext) {
        var snapshot = RenderSnapshot()

        if let entity = world.entities(with: Camera.self).first,
            let camera = world.get(Camera.self, for: entity),
            let transform = world.get(Transform.self, for: entity)
        {
            snapshot.viewProjection =
                Math.perspective(
                    fovDegrees: frame.configuration.fieldOfView, aspect: frame.aspectRatio, near: camera.near,
                    far: camera.far) * transform.matrix.inverse
        }

        if let entity = world.entities(with: DirectionalLight.self).first,
            let light = world.get(DirectionalLight.self, for: entity)
        {
            snapshot.light = light
        }

        for entity in world.entities(with: MeshRenderer.self) {
            guard let renderer = world.get(MeshRenderer.self, for: entity),
                let matrix = world.get(WorldTransform.self, for: entity)?.matrix
                    ?? world.get(Transform.self, for: entity)?.matrix
            else {
                continue
            }

            snapshot.objects.append(
                RenderObject(mesh: renderer.mesh, material: renderer.material, model: matrix))
        }

        frame.snapshot = snapshot
    }
}
