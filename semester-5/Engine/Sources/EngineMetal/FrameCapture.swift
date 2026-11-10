import EngineCore
import Foundation
import Metal
import simd

// MARK: - Captured resource data

public enum DebugPixelLayout: String, Codable, Sendable {
    case rgba16Float, rgba32Float, bgra8, rgba8, r32Float, r16Float, r8

    var bytesPerPixel: Int {
        switch self {
        case .rgba16Float:
            8
        case .rgba32Float:
            16
        case .bgra8, .rgba8, .r32Float:
            4
        case .r16Float:
            2
        case .r8:
            1
        }
    }
}

public struct CapturedTexture: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let width: Int
    public let height: Int
    public let samples: Int
    public let format: String
    public let isDepth: Bool
    public let isSRGB: Bool
    public let layout: DebugPixelLayout?
    public let bytesPerRow: Int
    public let bytesPerImage: Int
    public let bytes: Data
    public let note: String?

    public func pixel(x: Int, y: Int, sample: Int = 0) -> SIMD4<Float>? {
        guard let layout, (0..<width).contains(x), (0..<height).contains(y),
            (0..<samples).contains(sample)
        else {
            return nil
        }

        let offset = sample * bytesPerImage + y * bytesPerRow + x * layout.bytesPerPixel

        guard offset + layout.bytesPerPixel <= bytes.count else {
            return nil
        }

        func f32(_ index: Int) -> Float {
            bytes.withUnsafeBytes {
                Float(
                    bitPattern: UInt32(
                        littleEndian: $0.loadUnaligned(fromByteOffset: offset + index * 4, as: UInt32.self)))
            }
        }

        func f16(_ index: Int) -> Float {
            bytes.withUnsafeBytes { raw in
                BinaryScalar.float16(
                    UInt16(
                        littleEndian: raw.loadUnaligned(fromByteOffset: offset + index * 2, as: UInt16.self)))
            }
        }

        switch layout {
        case .rgba32Float:
            return SIMD4(f32(0), f32(1), f32(2), f32(3))
        case .rgba16Float:
            return SIMD4(f16(0), f16(1), f16(2), f16(3))
        case .bgra8:
            return SIMD4(
                Float(bytes[offset + 2]) / 255, Float(bytes[offset + 1]) / 255, Float(bytes[offset]) / 255,
                Float(bytes[offset + 3]) / 255)
        case .rgba8:
            return SIMD4(
                Float(bytes[offset]) / 255, Float(bytes[offset + 1]) / 255, Float(bytes[offset + 2]) / 255,
                Float(bytes[offset + 3]) / 255)
        case .r32Float:
            return SIMD4(repeating: f32(0))
        case .r16Float:
            return SIMD4(repeating: f16(0))
        case .r8:
            return SIMD4(repeating: Float(bytes[offset]) / 255)
        }
    }
}

public struct CapturedBuffer: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let length: Int
    public let sourceOffset: Int
    public let allocationLength: Int
    public let stride: Int?
    public let schema: String?
    public let bytes: Data
    public let note: String?
}

// MARK: - Captured frame data

public struct CapturedPass: Identifiable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let inputs: [String]
    public let outputs: [String]
    public let cpuMilliseconds: Double
    public let textures: [CapturedTexture]
    public let buffers: [CapturedBuffer]
}

public struct FrameCapture: Identifiable, Codable, Sendable {
    public let id: UInt64
    public let date: Date
    public let width: Int
    public let height: Int
    public let sampleCount: Int
    public let passes: [CapturedPass]
    public let bytesStored: Int
    public let notes: [String]

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// MARK: - GPU readback

@MainActor struct InspectableBuffer {
    let buffer: any MTLBuffer
    let range: Range<Int>
    let stride: Int?
    let schema: String?
}

@MainActor final class CaptureRecorder {
    struct TextureReadback {
        let name: String
        let source: any MTLTexture
        let buffer: (any MTLBuffer)?
        let layout: DebugPixelLayout?
        let row: Int
        let image: Int
        let note: String?
    }

    struct BufferReadback {
        let name: String
        let source: InspectableBuffer
        let buffer: (any MTLBuffer)?
        let note: String?
    }

    struct PassReadback {
        let declaration: PassDeclaration
        let cpu: Double
        let textures: [TextureReadback]
        let buffers: [BufferReadback]
    }

    let metal: MetalContext
    let budget: Int
    var used = 0
    var notes: [String] = []
    var passes: [PassReadback] = []
    private var compute: [String: any MTLComputePipelineState] = [:]

    init(metal: MetalContext, budget: Int = 256 * 1024 * 1024) throws {
        self.metal = metal
        self.budget = budget

        for name in ["debugColorMS", "debugDepthMS"] {
            let descriptor = MTL4ComputePipelineDescriptor()
            let function = MTL4LibraryFunctionDescriptor()
            function.library = metal.library
            function.name = name
            descriptor.computeFunctionDescriptor = function
            compute[name] = try metal.compiler.makeComputePipelineState(descriptor: descriptor)
        }
    }

    private func staging(_ size: Int, frame: FrameResources) -> (any MTLBuffer)? {
        guard size > 0, size <= budget - used,
            let buffer = metal.device.makeBuffer(length: size, options: .storageModeShared)
        else {
            return nil
        }

        used += size
        frame.residency.addAllocation(buffer)
        frame.retained.append(buffer)
        return buffer
    }

    // MARK: - Pass capture

    func record(_ declaration: PassDeclaration, cpu: Double, context: PassContext) throws {
        var textures: [TextureReadback] = []
        var buffers: [BufferReadback] = []

        guard let encoder = context.commands.makeComputeCommandEncoder() else {
            throw EngineError.unavailable("Could not create debugger readback encoder.")
        }

        encoder.label = "Debugger: \(declaration.name)"
        context.synchronize(encoder)

        defer {
            encoder.endEncoding()
        }

        let names = Set(
            declaration.inputs.map(\.name) + declaration.outputs.map(\.name)
                + Array(context.frame.debugTextures.keys)
        ).sorted()

        for name in names {
            guard let texture = context.frame.debugTextures[name] ?? context.frame.targets[name] else {
                continue
            }

            let depth = texture.pixelFormat == .depth32Float
            var layout: DebugPixelLayout?

            switch texture.pixelFormat {
            case .rgba16Float:
                layout = .rgba16Float
            case .rgba32Float:
                layout = .rgba32Float
            case .bgra8Unorm, .bgra8Unorm_srgb:
                layout = .bgra8
            case .rgba8Unorm, .rgba8Unorm_srgb:
                layout = .rgba8
            case .depth32Float, .r32Float:
                layout = .r32Float
            case .r16Float:
                layout = .r16Float
            case .r8Unorm:
                layout = .r8
            default:
                layout = nil
            }

            var note: String?

            if texture.storageMode == .memoryless {
                note = "Memoryless attachment has no stored contents. Use a stored debug attachment."
            }

            if texture.textureType != .type2D && texture.textureType != .type2DMultisample {
                note =
                    "Built-in preview supports 2D textures. Inspect other texture types in Xcode GPU capture."
            }

            if texture.isFramebufferOnly {
                note = "Framebuffer-only texture cannot be read. Disable framebufferOnly for capture."
            }

            if layout == nil {
                note =
                    "Preview format unsupported; metadata retained. Use Xcode GPU capture for this format."
            }

            if texture.sampleCount > 1 {
                layout = .rgba32Float
            }

            let row =
                texture.sampleCount > 1
                ? texture.width * 16 : ((texture.width * (layout?.bytesPerPixel ?? 1) + 255) / 256) * 256
            let image = row * texture.height
            var destination: (any MTLBuffer)?

            if note == nil {
                destination = staging(image * texture.sampleCount, frame: context.frame)

                if destination == nil {
                    note = "Capture memory budget exceeded (\(budget / 1024 / 1024) MiB)."
                }
            }

            if let destination {
                if texture.sampleCount > 1 {
                    guard texture.usage.contains(.shaderRead),
                        let state = compute[depth ? "debugDepthMS" : "debugColorMS"]
                    else {
                        throw EngineError.unavailable(
                            "MSAA capture requires shader-readable stored attachments.")
                    }

                    let descriptor = MTL4ArgumentTableDescriptor()
                    descriptor.maxBufferBindCount = 1
                    descriptor.maxTextureBindCount = 1
                    let table = try metal.device.makeArgumentTable(descriptor: descriptor)
                    table.setAddress(destination.gpuAddress, index: 0)
                    table.setTexture(texture.gpuResourceID, index: 0)
                    context.retain(table)
                    context.retain(state)
                    encoder.setComputePipelineState(state)
                    encoder.setArgumentTable(table)
                    encoder.dispatchThreads(
                        threadsPerGrid: MTLSize(
                            width: texture.width, height: texture.height, depth: texture.sampleCount),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
                } else {
                    encoder.copy(
                        sourceTexture: texture, sourceSlice: 0, sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                        destinationBuffer: destination, destinationOffset: 0, destinationBytesPerRow: row,
                        destinationBytesPerImage: image)
                }
            }

            textures.append(
                TextureReadback(
                    name: name, source: texture, buffer: destination, layout: layout, row: row, image: image,
                    note: note))
        }

        for (name, source) in context.frame.debugBuffers.sorted(by: { $0.key < $1.key }) {
            let size = source.range.count
            let destination = staging(size, frame: context.frame)

            if let destination {
                encoder.copy(
                    sourceBuffer: source.buffer, sourceOffset: source.range.lowerBound,
                    destinationBuffer: destination, destinationOffset: 0, size: size)
            }

            buffers.append(
                BufferReadback(
                    name: name, source: source, buffer: destination,
                    note: destination == nil
                        ? (size == 0 ? "No active elements." : "Capture memory budget exceeded.") : nil))
        }

        passes.append(
            PassReadback(declaration: declaration, cpu: cpu, textures: textures, buffers: buffers))
    }

    // MARK: - Capture assembly

    func finish(id: UInt64, size: SIMD2<Int>, samples: Int) -> FrameCapture {
        let snapshots = passes.enumerated().map { index, pass in
            let textures = pass.textures.map { texture in
                CapturedTexture(
                    id: "\(index).texture.\(texture.name)", name: texture.name, width: texture.source.width,
                    height: texture.source.height, samples: texture.source.sampleCount,
                    format: String(describing: texture.source.pixelFormat),
                    isDepth: texture.source.pixelFormat == .depth32Float,
                    isSRGB: texture.source.sampleCount == 1
                        && [.bgra8Unorm_srgb, .rgba8Unorm_srgb].contains(texture.source.pixelFormat),
                    layout: texture.layout, bytesPerRow: texture.row, bytesPerImage: texture.image,
                    bytes: texture.buffer.map { Data(bytes: $0.contents(), count: $0.length) } ?? Data(),
                    note: texture.note)
            }
            let buffers = pass.buffers.map { item in
                CapturedBuffer(
                    id: "\(index).buffer.\(item.name)", name: item.name, length: item.source.range.count,
                    sourceOffset: item.source.range.lowerBound, allocationLength: item.source.buffer.length,
                    stride: item.source.stride, schema: item.source.schema,
                    bytes: item.buffer.map { Data(bytes: $0.contents(), count: $0.length) } ?? Data(),
                    note: item.note)
            }
            return CapturedPass(
                id: index, name: pass.declaration.name, inputs: pass.declaration.inputs.map(\.name),
                outputs: pass.declaration.outputs.map(\.name), cpuMilliseconds: pass.cpu,
                textures: textures, buffers: buffers)
        }
        return FrameCapture(
            id: id, date: Date(), width: size.x, height: size.y, sampleCount: samples, passes: snapshots,
            bytesStored: used, notes: notes)
    }
}
