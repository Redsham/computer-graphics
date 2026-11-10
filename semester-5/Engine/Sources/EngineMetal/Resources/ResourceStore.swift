import EngineCore
import GPUShared
import Metal
import simd

// MARK: - Persistent resources

@MainActor public final class ResourceStore {
    public struct Mesh {
        public let buffer: any MTLBuffer
        public let count: Int
    }

    private let device: any MTLDevice
    private let log: EngineLog?
    private var nextID: UInt64 = 0
    private var meshes: [MeshID: Mesh] = [:]
    private var materials: [MaterialID: Material] = [:]

    init(device: any MTLDevice, log: EngineLog? = nil) {
        self.device = device
        self.log = log
    }

    public func makeMesh(vertices: [MeshVertex]) throws -> MeshID {
        guard !vertices.isEmpty, vertices.count.isMultiple(of: 3) else {
            throw EngineError.unavailable("Triangle mesh requires a nonempty multiple of three vertices.")
        }

        let data = vertices.map {
            GPUVertex(position: SIMD4($0.position, 1), normal: SIMD4($0.normal, 0))
        }

        guard
            let buffer = device.makeBuffer(
                bytes: data, length: data.count * MemoryLayout<GPUVertex>.stride,
                options: .storageModeShared)
        else {
            throw EngineError.unavailable("Could not allocate mesh buffer.")
        }

        nextID += 1
        let id = MeshID(nextID)
        buffer.label = "Mesh.\(nextID)"
        meshes[id] = Mesh(buffer: buffer, count: data.count)
        log?.write(
            .debug, category: "Resources",
            "Created mesh \(id.rawValue): \(data.count) vertices, \(buffer.length) bytes.")
        return id
    }

    public func makeMaterial(_ material: Material) -> MaterialID {
        nextID += 1
        let id = MaterialID(nextID)
        materials[id] = material
        return id
    }

    public func mesh(_ id: MeshID) throws -> Mesh {
        guard let mesh = meshes[id] else {
            throw EngineError.unavailable("Unknown mesh ID \(id.rawValue).")
        }

        return mesh
    }

    public func material(_ id: MaterialID) throws -> Material {
        guard let material = materials[id] else {
            throw EngineError.unavailable("Unknown material ID \(id.rawValue).")
        }

        return material
    }

    /// Submitted frames retain mesh buffers until GPU completion.
    public func removeMesh(_ id: MeshID) {
        meshes.removeValue(forKey: id)
        log?.write(.debug, category: "Resources", "Released mesh \(id.rawValue).")
    }

    public func removeMaterial(_ id: MaterialID) {
        materials.removeValue(forKey: id)
    }
}
