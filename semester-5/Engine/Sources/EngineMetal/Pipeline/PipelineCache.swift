import EngineCore
import Foundation
import Metal

// MARK: - Pipeline cache

@MainActor final class PipelineCache {
    private struct Key: Hashable {
        let vertex: String
        let fragment: String
        let format: UInt
        let library: ObjectIdentifier
        let samples: Int
    }

    private var values: [Key: any MTLRenderPipelineState] = [:]
    private var libraries: [ObjectIdentifier: any MTLLibrary] = [:]
    private let context: MetalContext

    init(context: MetalContext) {
        self.context = context
    }

    func pipeline(
        vertex: String, fragment: String, format: MTLPixelFormat,
        samples: Int = 1, library: (any MTLLibrary)? = nil
    ) throws -> any MTLRenderPipelineState {
        let library = library ?? context.library
        let key = Key(
            vertex: vertex, fragment: fragment, format: format.rawValue,
            library: ObjectIdentifier(library),
            samples: samples)

        if let cached = values[key] {
            return cached
        }

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "\(vertex)/\(fragment)/\(samples)"
        let vs = MTL4LibraryFunctionDescriptor()
        vs.library = library
        vs.name = vertex
        let fs = MTL4LibraryFunctionDescriptor()
        fs.library = library
        fs.name = fragment
        descriptor.vertexFunctionDescriptor = vs
        descriptor.fragmentFunctionDescriptor = fs
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.rasterSampleCount = samples
        let pipeline = try context.compiler.makeRenderPipelineState(descriptor: descriptor)
        libraries[ObjectIdentifier(library)] = library
        values[key] = pipeline
        return pipeline
    }
}
