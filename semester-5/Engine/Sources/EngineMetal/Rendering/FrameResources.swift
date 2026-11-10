import EngineCore
import GPUShared
import Metal
import simd

// MARK: - Per-frame resources

@MainActor public final class FrameResources {
    public let index: Int
    let allocator: any MTL4CommandAllocator
    var commands: any MTL4CommandBuffer
    public let forwardArguments: any MTL4ArgumentTable
    public let outputArguments: any MTL4ArgumentTable
    let uniforms: any MTLBuffer
    var objects: any MTLBuffer
    var capacity = 256
    public internal(set) var isCapturing = false
    var debugBuffers: [String: InspectableBuffer] = [:]
    var debugTextures: [String: any MTLTexture] = [:]
    var counters: (any MTL4CounterHeap)?
    var pendingProfile: (id: UInt64, names: [String])?
    var drawCount = 0

    /// Expose custom pass resources to the debugger. Register before GPU submission.
    public func inspectBuffer(
        _ name: String, buffer: any MTLBuffer, range: Range<Int>? = nil, stride: Int? = nil,
        schema: String? = nil
    ) {
        let range = range ?? 0..<buffer.length

        guard range.lowerBound >= 0, range.upperBound <= buffer.length else {
            return
        }

        debugBuffers[name] = InspectableBuffer(
            buffer: buffer, range: range, stride: stride, schema: schema)
    }

    public func inspectTexture(_ name: String, texture: any MTLTexture) {
        debugTextures[name] = texture
    }

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
        else {
            throw EngineError.unavailable("Could not allocate frame slot.")
        }

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

        if !isCapturing {
            return
        }

        if let buffer = allocation as? any MTLBuffer,
            !debugBuffers.values.contains(where: {
                ObjectIdentifier($0.buffer) == ObjectIdentifier(buffer)
            })
        {
            inspectBuffer(buffer.label ?? "Buffer.\(debugBuffers.count)", buffer: buffer)
        }

        if let texture = allocation as? any MTLTexture {
            inspectTexture(texture.label ?? "Texture.\(debugTextures.count)", texture: texture)
        }
    }
}
