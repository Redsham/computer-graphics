import EngineCore
import EngineMac

@MainActor enum SandboxScene {
    static func populate(_ session: EngineSession) throws {
        let cube = try session.renderer.resources.makeCube()
        let material = session.renderer.resources.makeMaterial(
            Material(baseColor: SIMD3(0.12, 0.55, 0.85)))
        let object = session.world.create()
        session.world.set(Transform(), for: object)
        session.world.set(WorldTransform(Transform().matrix), for: object)
        session.world.set(MeshRenderer(mesh: cube, material: material), for: object)
        session.world.set(Spin(), for: object)
        let camera = session.world.create()
        session.world.set(Transform(position: SIMD3(0, 0, 4)), for: camera)
        session.world.set(Camera(), for: camera)
        let light = session.world.create()
        session.world.set(DirectionalLight(), for: light)
    }
}
