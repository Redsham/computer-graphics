import simd

@MainActor public final class FrameContext {
  public var deltaTime: Float = 0
  public var aspectRatio: Float = 1
  public var input = InputSnapshot()
  public var configuration = EngineConfiguration()
  public var snapshot = RenderSnapshot()
  public init() {}
}
@MainActor public protocol EngineSystem: AnyObject {
  func start(world: World)
  func update(world: World, frame: FrameContext)
  func stop(world: World)
}
extension EngineSystem {
  public func start(world: World) {}
  public func stop(world: World) {}
}
@MainActor public final class SystemScheduler {
  private let systems: [any EngineSystem]
  private var started = false
  public init(systems: [any EngineSystem]) { self.systems = systems }
  public func start(world: World) {
    guard !started else { return }
    started = true
    for system in systems { system.start(world: world) }
  }
  public func update(world: World, frame: FrameContext) {
    start(world: world)
    world.beginUpdate()
    for system in systems { system.update(world: world, frame: frame) }
    world.endUpdate()
  }
  public func stop(world: World) {
    guard started else { return }
    for system in systems.reversed() { system.stop(world: world) }
    started = false
  }
}
@MainActor public final class CameraControlSystem: EngineSystem {
  public init() {}
  public func update(world: World, frame: FrameContext) {
    for entity in world.entities(with: Camera.self) {
      guard var camera = world.get(Camera.self, for: entity),
        var transform = world.get(Transform.self, for: entity)
      else { continue }
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
@MainActor public final class SpinSystem: EngineSystem {
  public init() {}
  public func update(world: World, frame: FrameContext) {
    for entity in world.entities(with: Spin.self) {
      guard let spin = world.get(Spin.self, for: entity),
        var transform = world.get(Transform.self, for: entity)
      else { continue }
      transform.rotation = simd_normalize(
        simd_quatf(angle: spin.speed * frame.deltaTime, axis: simd_normalize(SIMD3(0.3, 1, 0)))
          * transform.rotation)
      world.set(transform, for: entity)
    }
  }
}
@MainActor public final class TransformSystem: EngineSystem {
  public init() {}
  public func update(world: World, frame: FrameContext) {
    for entity in world.entities(with: Transform.self) {
      guard let transform = world.get(Transform.self, for: entity) else { continue }
      if world.get(WorldTransform.self, for: entity) != nil {
        world.set(WorldTransform(transform.matrix), for: entity)
      } else {
        world.deferMutation { $0.set(WorldTransform(transform.matrix), for: entity) }
      }
    }
  }
}
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
      else { continue }
      snapshot.objects.append(
        RenderObject(mesh: renderer.mesh, material: renderer.material, model: matrix))
    }
    frame.snapshot = snapshot
  }
}
