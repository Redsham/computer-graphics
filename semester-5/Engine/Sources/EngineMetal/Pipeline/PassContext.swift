import EngineCore
import Metal

// MARK: - Pass contexts

@MainActor public struct PassPreparationContext {
    public let metal: MetalContext
    public let configuration: EngineConfiguration
    let cache: PipelineCache

    public func pipeline(
        vertex: String, fragment: String, color: MTLPixelFormat,
        samples: Int = 1, library: (any MTLLibrary)? = nil
    ) throws -> any MTLRenderPipelineState {
        try cache.pipeline(
            vertex: vertex, fragment: fragment, format: color, samples: samples, library: library)
    }
}

@MainActor public struct PassContext {
    public let commands: any MTL4CommandBuffer
    public let frame: FrameResources
    public let resources: ResourceStore
    public let snapshot: RenderSnapshot
    public let configuration: EngineConfiguration

    public func texture(_ name: String) throws -> any MTLTexture {
        guard let texture = frame.targets[name] else {
            throw EngineError.invalidPipeline("Texture \(name) is unavailable.")
        }

        return texture
    }

    public func recordDraw(count: Int = 1) {
        frame.drawCount += max(0, count)
    }

    public func retain(_ resource: AnyObject) {
        frame.retained.append(resource)
    }

    /// Every pass starts after prior GPU accesses. Conservative and correct for custom passes.
    public func synchronize(_ encoder: any MTL4CommandEncoder) {
        encoder.barrier(afterQueueStages: .all, beforeStages: .all, visibilityOptions: .device)
    }
}
