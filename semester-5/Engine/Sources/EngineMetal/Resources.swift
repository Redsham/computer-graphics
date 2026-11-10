import EngineCore
import GPUShared
import Metal
import simd

public struct MeshVertex: Sendable {
  public var position: SIMD3<Float>
  public var normal: SIMD3<Float>
  public init(position: SIMD3<Float>, normal: SIMD3<Float>) {
    self.position = position
    self.normal = normal
  }
}
@MainActor public final class ResourceStore {
  public struct Mesh {
    public let buffer: any MTLBuffer
    public let count: Int
  }
  private let device: any MTLDevice
  private var nextID: UInt64 = 0
  private var meshes: [MeshID: Mesh] = [:]
  private var materials: [MaterialID: Material] = [:]
  init(device: any MTLDevice) { self.device = device }
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
    else { throw EngineError.unavailable("Could not allocate mesh buffer.") }
    nextID += 1
    let id = MeshID(nextID)
    buffer.label = "Mesh.\(nextID)"
    meshes[id] = Mesh(buffer: buffer, count: data.count)
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
  public func removeMesh(_ id: MeshID) { meshes.removeValue(forKey: id) }
  public func removeMaterial(_ id: MaterialID) { materials.removeValue(forKey: id) }
  public func makeCube() throws -> MeshID {
    let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
      (SIMD3(0, 0, 1), [SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)]),
      (SIMD3(0, 0, -1), [SIMD3(1, -1, -1), SIMD3(-1, -1, -1), SIMD3(-1, 1, -1), SIMD3(1, 1, -1)]),
      (SIMD3(1, 0, 0), [SIMD3(1, -1, 1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(1, 1, 1)]),
      (SIMD3(-1, 0, 0), [SIMD3(-1, -1, -1), SIMD3(-1, -1, 1), SIMD3(-1, 1, 1), SIMD3(-1, 1, -1)]),
      (SIMD3(0, 1, 0), [SIMD3(-1, 1, 1), SIMD3(1, 1, 1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1)]),
      (SIMD3(0, -1, 0), [SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, -1, 1), SIMD3(-1, -1, 1)]),
    ]
    let vertices = faces.flatMap { normal, corners in
      [0, 1, 2, 0, 2, 3].map { MeshVertex(position: corners[$0] * 0.75, normal: normal) }
    }
    return try makeMesh(vertices: vertices)
  }
}

@MainActor public final class FrameResources {
  public let index: Int
  let allocator: any MTL4CommandAllocator
  let commands: any MTL4CommandBuffer
  public let forwardArguments: any MTL4ArgumentTable
  public let outputArguments: any MTL4ArgumentTable
  let uniforms: any MTLBuffer
  var objects: any MTLBuffer
  var capacity = 256
  let residency: any MTLResidencySet
  var completionValue: UInt64 = 0
  var targets: [String: any MTLTexture] = [:]
  var layout: [TextureContract] = []
  var size = SIMD2<Int>.zero
  var samples = 0
  // Explicit retention is required: Metal 4 command buffers do not retain resources.
  var retained: [AnyObject] = []
  init(device: any MTLDevice, index: Int) throws {
    guard let allocator = device.makeCommandAllocator(), let commands = device.makeCommandBuffer(),
      let uniforms = device.makeBuffer(
        length: MemoryLayout<GPUFrame>.stride, options: .storageModeShared),
      let objects = device.makeBuffer(
        length: 256 * MemoryLayout<GPUObject>.stride, options: .storageModeShared)
    else { throw EngineError.unavailable("Could not allocate frame slot.") }
    self.index = index
    self.allocator = allocator
    self.commands = commands
    self.uniforms = uniforms
    self.objects = objects
    let descriptor = MTL4ArgumentTableDescriptor()
    descriptor.maxBufferBindCount = 3
    descriptor.maxTextureBindCount = 1
    descriptor.initializeBindings = true
    forwardArguments = try device.makeArgumentTable(descriptor: descriptor)
    outputArguments = try device.makeArgumentTable(descriptor: descriptor)
    let residentDescriptor = MTLResidencySetDescriptor()
    residentDescriptor.initialCapacity = 16
    residency = try device.makeResidencySet(descriptor: residentDescriptor)
  }
  /// Register pass-owned buffers/textures in prepareFrame, before residency is committed.
  public func useResource(_ allocation: any MTLAllocation) {
    residency.addAllocation(allocation)
    retained.append(allocation)
  }
  func upload(
    snapshot: RenderSnapshot, configuration: EngineConfiguration, resources: ResourceStore,
    device: any MTLDevice
  ) throws {
    if snapshot.objects.count > capacity {
      capacity = max(snapshot.objects.count, capacity * 2)
      guard
        let buffer = device.makeBuffer(
          length: capacity * MemoryLayout<GPUObject>.stride, options: .storageModeShared)
      else { throw EngineError.unavailable("Could not grow object buffer.") }
      objects = buffer
    }
    var frame = GPUFrame(
      viewProjection: snapshot.viewProjection,
      lightDirection: SIMD4(snapshot.light.direction, 0),
      lightColor: SIMD4(snapshot.light.color * snapshot.light.intensity, 1),
      parameters: SIMD4(configuration.exposure, 0, 0, 0))
    uniforms.contents().copyMemory(from: &frame, byteCount: MemoryLayout<GPUFrame>.stride)
    let destination = objects.contents().bindMemory(to: GPUObject.self, capacity: capacity)
    for (index, object) in snapshot.objects.enumerated() {
      let material = try resources.material(object.material)
      guard abs(simd_determinant(object.model)) > 0.000001 else {
        throw EngineError.unavailable("Non-invertible model transform.")
      }
      destination[index] = GPUObject(
        model: object.model, normalMatrix: object.model.inverse.transpose,
        baseColor: SIMD4(material.baseColor, 1))
    }
  }
}
