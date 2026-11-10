import EngineCore
import Metal

/// Owns pass preparation and validated screen-resource layouts, independent of frame submission.
@MainActor final class RenderPipelinePlan {
    let passes: [any RenderPass]
    private let metal: MetalContext
    private let cache: PipelineCache
    private var preparedConfiguration: EngineConfiguration?
    private(set) var contracts: [TextureContract] = []
    private(set) var declarations: [PassDeclaration] = []
    private(set) var names: [String] = []

    init(metal: MetalContext, passes: [any RenderPass]) {
        self.metal = metal
        self.passes = passes
        cache = PipelineCache(context: metal)
    }

    func prepare(configuration: EngineConfiguration) throws {
        guard preparedConfiguration != configuration else {
            return
        }

        guard metal.device.supportsTextureSampleCount(configuration.sampleCount) else {
            throw EngineError.invalidConfiguration("GPU does not support selected MSAA.")
        }

        let declarations = passes.map { $0.declaration(configuration: configuration) }
        let nextContracts = try PipelineValidation.validate(declarations)
        let context = PassPreparationContext(metal: metal, configuration: configuration, cache: cache)
        // A pass can replace its state before a later pass fails. Any retry must prepare the whole plan.
        preparedConfiguration = nil

        for pass in passes {
            try pass.prepare(context)
        }

        self.declarations = declarations
        names = declarations.enumerated().map { "\($0.offset + 1). \($0.element.name)" }
        contracts = nextContracts
        preparedConfiguration = configuration
    }

    func updateTargets(frame: FrameResources, size: SIMD2<Int>, samples: Int) throws {
        guard frame.size != size || frame.samples != samples || frame.layout != contracts else {
            return
        }

        var targets: [String: any MTLTexture] = [:]

        for contract in contracts where contract.name != "surface" {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: contract.format, width: size.x, height: size.y, mipmapped: false)
            descriptor.sampleCount = contract.samples
            descriptor.textureType = contract.samples > 1 ? .type2DMultisample : .type2D
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]

            guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
                throw EngineError.unavailable("Could not allocate \(contract.name).")
            }

            texture.label = contract.name
            targets[contract.name] = texture
        }

        frame.targets = targets
        frame.size = size
        frame.samples = samples
        frame.layout = contracts
    }
}
