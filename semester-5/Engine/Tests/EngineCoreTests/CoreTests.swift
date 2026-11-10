import EngineCore
import XCTest
import simd

@MainActor final class CoreTests: XCTestCase {
  func testEntityGenerationAndComponentRemoval() {
    let world = World()
    let first = world.create()
    world.set(Transform(position: SIMD3(1, 2, 3)), for: first)
    world.destroy(first)
    let second = world.create()
    XCTAssertEqual(first.index, second.index)
    XCTAssertNotEqual(first.generation, second.generation)
    XCTAssertFalse(world.isAlive(first))
    XCTAssertTrue(world.isAlive(second))
    world.set(Camera(), for: first)
    XCTAssertNil(world.get(Camera.self, for: second))
    XCTAssertNil(world.get(Transform.self, for: first))
    world.set(Camera(), for: second)
    world.remove(Camera.self, from: second)
    XCTAssertTrue(world.entities(with: Camera.self).isEmpty)
  }
  func testDeferredStructuralChangesAndLifecycleOrder() {
    let world = World()
    let entity = world.create()
    let trace = Trace()
    let scheduler = SystemScheduler(systems: [
      Probe("A", trace: trace, entity: entity), Probe("B", trace: trace, entity: entity),
    ])
    scheduler.update(world: world, frame: FrameContext())
    XCTAssertEqual(trace.events, ["start A", "start B", "update A", "update B"])
    XCTAssertEqual(trace.observed, [false, false])
    XCTAssertNotNil(world.get(Camera.self, for: entity))
    scheduler.stop(world: world)
    scheduler.stop(world: world)
    XCTAssertEqual(Array(trace.events.suffix(2)), ["stop B", "stop A"])
  }
  func testPerspectiveDepthAndCameraView() {
    let p = Math.perspective(fovDegrees: 60, aspect: 2, near: 0.1, far: 100)
    let near = p * SIMD4<Float>(0, 0, -0.1, 1)
    let far = p * SIMD4<Float>(0, 0, -100, 1)
    XCTAssertEqual(near.z / near.w, 0, accuracy: 0.00001)
    XCTAssertEqual(far.z / far.w, 1, accuracy: 0.00001)
    XCTAssertEqual(p.columns.1.y / p.columns.0.x, 2, accuracy: 0.00001)
    let camera = Transform(position: SIMD3(0, 0, 4))
    let origin = camera.matrix.inverse * SIMD4<Float>(0, 0, 0, 1)
    XCTAssertEqual(origin.z, -4, accuracy: 0.00001)
  }
  func testFrameClockUsesActualTimeAndClampsPause() {
    var clock = FrameClock()
    XCTAssertEqual(clock.tick(at: 1), 0)
    XCTAssertEqual(clock.tick(at: 1.02), 0.02, accuracy: 0.00001)
    XCTAssertEqual(clock.tick(at: 20), 0.1)
    XCTAssertEqual(clock.tick(at: 19), 0)
    clock.reset()
    XCTAssertEqual(clock.tick(at: 25), 0)
  }
  func testConfigurationValidationPersistenceAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ConfigurationStore(
      defaultsData: JSONEncoder().encode(EngineConfiguration()),
      userURL: directory.appending(path: "settings.json"))
    XCTAssertNil(store.load().warning)
    var settings = EngineConfiguration()
    settings.sampleCount = 4
    settings.exposure = 2
    try store.save(settings)
    XCTAssertEqual(store.load().configuration, settings)
    try Data("broken".utf8).write(to: store.userURL)
    XCTAssertEqual(store.load().configuration, store.defaults)
    XCTAssertNotNil(store.load().warning)
    settings.fieldOfView = .nan
    XCTAssertThrowsError(try settings.validated())
    settings = EngineConfiguration()
    settings.sampleCount = 2
    XCTAssertThrowsError(try store.save(settings))
    settings = EngineConfiguration()
    settings.background.x = 2
    XCTAssertThrowsError(try settings.validated())
  }
  func testCameraAndExtractionFollowSystemUpdates() throws {
    let world = World()
    let camera = world.create()
    world.set(Camera(), for: camera)
    world.set(Transform(position: SIMD3(0, 0, 4)), for: camera)
    let cube = world.create()
    world.set(Transform(), for: cube)
    world.set(MeshRenderer(mesh: MeshID(1), material: MaterialID(2)), for: cube)
    world.set(Spin(speed: 1), for: cube)
    let frame = FrameContext()
    frame.deltaTime = 0.1
    frame.input = InputSnapshot(movement: SIMD3(0, 0, -1))
    let scheduler = SystemScheduler(systems: [
      CameraControlSystem(), SpinSystem(), TransformSystem(), RenderExtractionSystem(),
    ])
    scheduler.update(world: world, frame: frame)
    XCTAssertEqual(
      try XCTUnwrap(world.get(Transform.self, for: camera)).position.z, 3.7, accuracy: 0.00001)
    XCTAssertEqual(frame.snapshot.objects.count, 1)
    XCTAssertNotEqual(frame.snapshot.objects[0].model.columns.0.z, 0)
    scheduler.stop(world: world)
  }
}
@MainActor private final class Trace {
  var events: [String] = []
  var observed: [Bool] = []
}
@MainActor private final class Probe: EngineSystem {
  let name: String
  let trace: Trace
  let entity: Entity
  init(_ name: String, trace: Trace, entity: Entity) {
    self.name = name
    self.trace = trace
    self.entity = entity
  }
  func start(world: World) { trace.events.append("start \(name)") }
  func update(world: World, frame: FrameContext) {
    trace.events.append("update \(name)")
    trace.observed.append(world.get(Camera.self, for: entity) != nil)
    world.deferMutation { $0.set(Camera(), for: self.entity) }
  }
  func stop(world: World) { trace.events.append("stop \(name)") }
}
