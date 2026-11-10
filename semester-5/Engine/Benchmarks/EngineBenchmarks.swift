import EngineCore
import Foundation

/// Headless CPU measurements. GPU workloads are measured separately through Xcode and FrameProfile.
@main @MainActor enum EngineBenchmarks {
    struct Sample: Codable {
        let name: String
        let iterations: Int
        let medianMilliseconds: Double
        let minimumMilliseconds: Double
        let maximumMilliseconds: Double
        let checksum: Int
    }

    struct Report: Codable {
        let date: Date
        let operatingSystem: String
        let processors: Int
        let samples: [Sample]
    }

    static func measure(_ name: String, iterations: Int, run: () -> Int) -> Sample {
        _ = run()
        var times: [Double] = []
        var checksum = 0

        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= run()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }

        times.sort()
        return Sample(
            name: name, iterations: iterations, medianMilliseconds: times[times.count / 2],
            minimumMilliseconds: times[0], maximumMilliseconds: times[times.count - 1], checksum: checksum)
    }

    static func main() throws {
        let world = World()

        for _ in 0..<10_000 {
            world.set(Camera(), for: world.create())
        }

        let queries = measure("stable-component-queries-10000", iterations: 1000) {
            var checksum = 0

            for _ in 0..<1000 {
                checksum &+= world.entities(with: Camera.self).count
            }

            return checksum
        }

        let history = ProfileHistory(capacity: 300)
        var frameID: UInt64 = 0
        let profiles = measure("profile-history-append-300", iterations: 100_000) {
            for _ in 0..<100_000 {
                frameID &+= 1
                history.append(FrameProfile(id: frameID, cpuMilliseconds: 1))
            }

            return history.frames.count
        }

        let scene = World()

        for _ in 0..<1000 {
            let entity = scene.create()
            scene.set(Transform(), for: entity)
            scene.set(WorldTransform(Transform().matrix), for: entity)
            scene.set(Spin(), for: entity)
            scene.set(MeshRenderer(mesh: MeshID(1), material: MaterialID(1)), for: entity)
        }

        let scheduler = SystemScheduler(systems: [SpinSystem(), TransformSystem(), RenderExtractionSystem()])
        let frame = FrameContext()
        frame.deltaTime = 1 / 60
        let systems = measure("scene-update-1000-objects", iterations: 100) {
            for _ in 0..<100 {
                scheduler.update(world: scene, frame: frame)
            }

            return frame.snapshot.objects.count
        }
        scheduler.stop(world: scene)

        let report = Report(
            date: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            processors: ProcessInfo.processInfo.processorCount, samples: [queries, profiles, systems])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)

        if CommandLine.arguments.count == 2 {
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
