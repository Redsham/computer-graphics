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

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

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

    func start(world: World) {
        trace.events.append("start \(name)")
    }

    func update(world: World, frame: FrameContext) {
        trace.events.append("update \(name)")
        trace.observed.append(world.get(Camera.self, for: entity) != nil)
        world.deferMutation { $0.set(Camera(), for: self.entity) }
    }

    func stop(world: World) {
        trace.events.append("stop \(name)")
    }
}

extension CoreTests {
    func testConsoleParsingHistoryAndRegistration() throws {
        XCTAssertEqual(
            try ConsoleParser.tokenize("echo \"two words\" '' a\\ b"), ["echo", "two words", "", "a b"])
        XCTAssertThrowsError(try ConsoleParser.tokenize("echo 'missing"))
        let commands = ConsoleCommands()
        commands.register("echo", help: "Print text") { $0.joined(separator: " ") }
        XCTAssertEqual(try commands.execute("echo hello"), "hello")
        XCTAssertEqual(commands.completions("ec"), ["echo"])
        XCTAssertTrue(commands.help.contains("Print text"))
        XCTAssertThrowsError(try commands.execute("unknown"))

        for index in 0..<220 {
            _ = try commands.execute("echo \(index)")
        }

        XCTAssertEqual(commands.history.count, 200)
    }

    func testBoundedStructuredLogFilteringExportAndRotation() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let log = try EngineLog(
            capacity: 3, fileURL: directory.appending(path: "engine.jsonl"), fileLimit: 1024)

        for index in 0..<8 {
            log.write(
                index.isMultiple(of: 2) ? .info : .warning, category: "Test",
                "\(index) " + String(repeating: "x", count: 700))
        }

        XCTAssertNil(log.flush())
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(log.filtered(minimum: .warning).count, 2)
        XCTAssertEqual(log.filtered(search: "Test").count, 3)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.appending(path: "engine.jsonl.1").path))
        let exported = try JSONSerialization.jsonObject(with: log.exportJSON()) as? [[String: Any]]
        XCTAssertEqual(exported?.count, 3)
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testProfileHistoryBoundsAndDelayedGPUResults() {
        let history = ProfileHistory(capacity: 3)

        for id in 0..<5 {
            history.append(FrameProfile(id: UInt64(id), cpuMilliseconds: Double(id)))
        }

        XCTAssertEqual(history.frames.map(\.id), [2, 3, 4])
        history.updateGPU(frameID: 3, total: 0.5, passes: [TimingSample("Forward", milliseconds: 0.3)])
        XCTAssertEqual(history.frames[1].gpuMilliseconds, 0.5)
        history.updateCPU(frameID: 3, total: 7, systems: [TimingSample("Camera", milliseconds: 0.1)])
        XCTAssertEqual(history.frames[1].cpuMilliseconds, 7)
        XCTAssertEqual(history.percentile(1), 7)
        history.updateGPU(frameID: 0, total: 100, passes: [])
        XCTAssertEqual(history.frames.count, 3)
    }
}

extension CoreTests {
    func testCachedQueriesInvalidateOnlyForStructuralChangesAndKeepSnapshotsStable() {
        let world = World()
        let first = world.create()
        world.set(Camera(), for: first)
        let frozen = world.entities(with: Camera.self)
        XCTAssertEqual(world.entities(with: Camera.self), frozen)
        world.set(Camera(), for: first)
        XCTAssertEqual(world.entities(with: Camera.self), frozen)

        let second = world.create()
        world.set(Camera(), for: second)
        XCTAssertEqual(world.entities(with: Camera.self), [first, second])
        XCTAssertEqual(frozen, [first])
        world.remove(Camera.self, from: first)
        XCTAssertEqual(world.entities(with: Camera.self), [second])
        world.destroy(second)
        XCTAssertTrue(world.entities(with: Camera.self).isEmpty)
        let recycled = world.create()
        world.set(Camera(), for: recycled)
        XCTAssertEqual(world.entities(with: Camera.self), [recycled])
        XCTAssertNotEqual(recycled, second)
    }

    func testDeferredInsertionInvalidatesPreviouslyCachedQuery() {
        let world = World()
        let entity = world.create()
        let trace = Trace()
        let scheduler = SystemScheduler(systems: [Probe("Insert", trace: trace, entity: entity)])
        XCTAssertTrue(world.entities(with: Camera.self).isEmpty)
        scheduler.update(world: world, frame: FrameContext())
        XCTAssertEqual(world.entities(with: Camera.self), [entity])
        XCTAssertEqual(trace.observed, [false])
        scheduler.stop(world: world)
    }

    func testProfileHistoryWraparoundUpdatesClearAndFrozenSnapshots() {
        let history = ProfileHistory(capacity: 1)
        history.append(FrameProfile(id: 1, cpuMilliseconds: 1))
        let frozen = history.frames
        history.append(FrameProfile(id: 2, cpuMilliseconds: 2))
        let revision = history.revision
        history.updateGPU(frameID: 1, total: 99, passes: [])
        XCTAssertEqual(history.revision, revision)
        history.updateGPU(frameID: 2, total: 0.5, passes: [])
        history.updateCPU(frameID: 2, total: 3, systems: [])
        XCTAssertEqual(history.frames.count, 1)
        XCTAssertEqual(history.frames[0].gpuMilliseconds, 0.5)
        XCTAssertEqual(history.frames[0].cpuMilliseconds, 3)
        XCTAssertEqual(frozen[0].id, 1)
        XCTAssertEqual(frozen[0].cpuMilliseconds, 1)
        history.clear()
        XCTAssertTrue(history.frames.isEmpty)
        history.append(FrameProfile(id: 3))
        XCTAssertEqual(history.frames.map(\.id), [3])
        XCTAssertGreaterThan(history.revision, revision)
    }

    func testLogWraparoundPreservesChronologyAndExportAfterClear() throws {
        let log = try EngineLog(capacity: 2)
        for index in 0..<5 {
            log.write(category: "Ring", "\(index)")
        }
        let frozen = log.entries
        XCTAssertEqual(frozen.map(\.message), ["3", "4"])
        log.clear()
        log.write(category: "Ring", "next")
        XCTAssertEqual(log.entries.map(\.message), ["next"])
        XCTAssertEqual(frozen.map(\.message), ["3", "4"])
        let decoded = try JSONDecoder.isoDates.decode([LogEntry].self, from: log.exportJSON())
        XCTAssertEqual(decoded.map(\.message), ["next"])
    }

    func testPortableHalfFloatDecodingIncludesSpecialValues() {
        XCTAssertEqual(BinaryScalar.float16(0x3c00), 1)
        XCTAssertEqual(BinaryScalar.float16(0xbc00), -1)
        XCTAssertEqual(BinaryScalar.float16(0x0001), pow(2, -24), accuracy: 1e-12)
        XCTAssertEqual(BinaryScalar.float16(0x8000).sign, .minus)
        XCTAssertEqual(BinaryScalar.float16(0x7c00), .infinity)
        XCTAssertTrue(BinaryScalar.float16(0x7e00).isNaN)
    }
}

private extension JSONDecoder {
    static var isoDates: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
