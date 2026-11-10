import EngineCore
import EngineMetal
import Metal
import XCTest
import simd

@MainActor final class MetalTests: XCTestCase {
    func testPassContractsRejectMissingInputsFormatsAndDuplicateOutputs() throws {
        let hdr = TextureContract("hdr", format: .rgba16Float)
        let surface = TextureContract("surface", format: .bgra8Unorm_srgb)
        let forward = PassDeclaration(name: "Forward", outputs: [hdr])
        let output = PassDeclaration(name: "Output", inputs: [hdr], outputs: [surface])
        XCTAssertEqual(try PipelineValidation.validate([forward, output]).count, 2)
        XCTAssertThrowsError(try PipelineValidation.validate([output, forward]))
        XCTAssertThrowsError(try PipelineValidation.validate([forward, forward, output]))
        XCTAssertThrowsError(
            try PipelineValidation.validate([
                forward,
                PassDeclaration(
                    name: "Wrong", inputs: [TextureContract("hdr", format: .rgba8Unorm)], outputs: [surface]),
            ]))
        XCTAssertThrowsError(
            try PipelineValidation.validate([
                forward,
                PassDeclaration(
                    name: "Wrong samples", inputs: [TextureContract("hdr", format: .rgba16Float, samples: 4)],
                    outputs: [surface]),
            ]))
    }

    func testOffscreenGeometryDepthExposureAndFrameReuse() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 GPU required")
        }

        let renderer = try MetalRenderer()
        let device = renderer.metal.device
        let cube = try renderer.resources.makeCube()
        let red = renderer.resources.makeMaterial(Material(baseColor: SIMD3(0.9, 0.03, 0.03)))
        let blue = renderer.resources.makeMaterial(Material(baseColor: SIMD3(0.03, 0.03, 0.9)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 128, height: 128, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        let surface = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var snapshot = RenderSnapshot()
        snapshot.viewProjection =
            Math.perspective(fovDegrees: 60, aspect: 1, near: 0.1, far: 100)
            * Math.translation(SIMD3(0, 0, -4))
        let front = RenderObject(mesh: cube, material: red, model: Math.translation(SIMD3(0, 0, 0.5)))
        let back = RenderObject(mesh: cube, material: blue, model: Math.translation(SIMD3(0, 0, -0.5)))
        snapshot.objects = [front, back]  // Farther geometry is submitted last: depth must reject it.
        var config = EngineConfiguration()
        config.background = .zero
        var gpuErrors: [String] = []
        renderer.onError = { gpuErrors.append($0) }

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: 4)
            surface.getBytes(&rgba, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            return rgba
        }

        try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
        try renderer.waitUntilIdle()
        let bright = pixel(64, 64)
        XCTAssertGreaterThan(
            Int(bright[2]), Int(bright[0]) * 2, "Near red cube must occlude far blue cube")
        XCTAssertGreaterThan(bright[2], 80)
        XCTAssertEqual(pixel(0, 0)[0], 0)
        snapshot.objects = [back, front]
        config.exposure = 0.2
        try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
        try renderer.waitUntilIdle()
        let dark = pixel(64, 64)
        XCTAssertLessThan(dark[2], bright[2])

        // More than three submissions and live MSAA changes exercise every slot's safe reuse.
        for index in 0..<12 {
            config.sampleCount = index.isMultiple(of: 2) ? 4 : 1
            config.wireframe = index.isMultiple(of: 3)
            try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
        }

        try renderer.waitUntilIdle()
        try renderer.render(snapshot: snapshot, configuration: config, surface: nil)
        let resizedDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 192, height: 96, mipmapped: false)
        resizedDescriptor.storageMode = .shared
        resizedDescriptor.usage = [.renderTarget]
        let resized = try XCTUnwrap(device.makeTexture(descriptor: resizedDescriptor))
        try renderer.render(snapshot: snapshot, configuration: config, surface: resized)
        // Removing a submitted mesh must not release buffers still used by the GPU.
        renderer.resources.removeMesh(cube)
        try renderer.waitUntilIdle()
        XCTAssertThrowsError(
            try renderer.render(snapshot: snapshot, configuration: config, surface: resized))
        snapshot.objects = []
        try renderer.render(snapshot: snapshot, configuration: config, surface: resized)
        try renderer.waitUntilIdle()
        XCTAssertTrue(gpuErrors.isEmpty)
    }
}

extension MetalTests {
    func testPreparationFailureRepreparesPreviouslyValidConfiguration() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 required")
        }

        XCTAssertThrowsError(try MetalRenderer(passes: []))
        let forward = InstrumentedForwardPass()
        let renderer = try MetalRenderer(passes: [forward, RejectMSAAOutputPass()])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 32, height: 32, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        let surface = try XCTUnwrap(renderer.metal.device.makeTexture(descriptor: descriptor))
        var configuration = EngineConfiguration()
        configuration.sampleCount = 4
        XCTAssertThrowsError(
            try renderer.render(
                snapshot: RenderSnapshot(), configuration: configuration, surface: surface))
        configuration.sampleCount = 1
        try renderer.render(snapshot: RenderSnapshot(), configuration: configuration, surface: surface)
        try renderer.waitUntilIdle()
        XCTAssertEqual(forward.preparations, 3)
        XCTAssertEqual(renderer.lastSubmittedFrameID, 1)
    }

    func testObjectBufferGrowthCapturesActiveRangeAndReusesSlots() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 required")
        }

        let renderer = try MetalRenderer()
        let cube = try renderer.resources.makeCube()
        let material = renderer.resources.makeMaterial(Material(baseColor: .one))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 32, height: 32, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let surface = try XCTUnwrap(renderer.metal.device.makeTexture(descriptor: descriptor))
        var snapshot = RenderSnapshot()
        snapshot.objects = Array(
            repeating: RenderObject(
                mesh: cube, material: material, model: Math.scale(SIMD3(repeating: 0.1))), count: 600)
        try renderer.requestCapture()
        try renderer.render(snapshot: snapshot, configuration: EngineConfiguration(), surface: surface)
        let capture = try XCTUnwrap(renderer.lastCapture)
        let objects = try XCTUnwrap(capture.passes[0].buffers.first { $0.name == "Objects" })
        XCTAssertEqual(objects.bytes.count, 600 * 144)
        XCTAssertGreaterThanOrEqual(objects.allocationLength, objects.bytes.count)

        snapshot.objects.removeAll()
        for _ in 0..<5 {
            try renderer.render(snapshot: snapshot, configuration: EngineConfiguration(), surface: surface)
        }
        try renderer.waitUntilIdle()
        XCTAssertEqual(renderer.profiles.frames.last?.drawCount, 1)
    }

    func testPassExtensionPreparationAndCaptureRemainIndependentOfCoordinator() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 required")
        }

        let pass = InstrumentedForwardPass()
        let renderer = try MetalRenderer(passes: [pass, OutputPass()])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 32, height: 32, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let surface = try XCTUnwrap(renderer.metal.device.makeTexture(descriptor: descriptor))
        var configuration = EngineConfiguration()

        for _ in 0..<5 {
            try renderer.render(snapshot: RenderSnapshot(), configuration: configuration, surface: surface)
        }

        try renderer.waitUntilIdle()
        XCTAssertEqual(pass.preparations, 1)
        XCTAssertEqual(pass.framePreparations, 5)
        configuration.sampleCount = 4
        try renderer.requestCapture()
        try renderer.render(snapshot: RenderSnapshot(), configuration: configuration, surface: surface)
        XCTAssertEqual(pass.preparations, 2)
        XCTAssertEqual(pass.framePreparations, 6)
        let capture = try XCTUnwrap(renderer.lastCapture)
        let buffer = try XCTUnwrap(capture.passes[0].buffers.first { $0.name == "Custom pass data" })
        XCTAssertEqual(buffer.bytes.count, 16)
        XCTAssertTrue(buffer.bytes.allSatisfy { $0 == 7 })
        XCTAssertEqual(capture.passes.map(\.name), ["Forward", "Output"])
    }

    func testDebuggerPreservesPassTexturesBuffersMSAASamplesAndTimestamps() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 required")
        }

        let renderer = try MetalRenderer()
        let cube = try renderer.resources.makeCube()
        let material = renderer.resources.makeMaterial(Material(baseColor: SIMD3(0.8, 0.2, 0.1)))
        var snapshot = RenderSnapshot()
        snapshot.viewProjection =
            Math.perspective(fovDegrees: 60, aspect: 1, near: 0.1, far: 100)
            * Math.translation(SIMD3(0, 0, -4))
        snapshot.objects = [
            RenderObject(mesh: cube, material: material, model: matrix_identity_float4x4)
        ]
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 64, height: 64, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let surface = try XCTUnwrap(renderer.metal.device.makeTexture(descriptor: descriptor))
        var config = EngineConfiguration()
        config.sampleCount = 4
        try renderer.requestCapture()
        try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
        let capture = try XCTUnwrap(renderer.lastCapture)
        XCTAssertEqual(capture.passes.map(\.name), ["Forward", "Output"])
        let forward = capture.passes[0]
        let depth = try XCTUnwrap(forward.textures.first(where: { $0.name == "depth" }))
        XCTAssertEqual(depth.samples, 4)
        XCTAssertLessThan(try XCTUnwrap(depth.pixel(x: 32, y: 32, sample: 3)).x, 1)
        XCTAssertEqual(try XCTUnwrap(depth.pixel(x: 0, y: 0, sample: 0)).x, 1, accuracy: 0.00001)
        let msaa = try XCTUnwrap(forward.textures.first(where: { $0.name == "msaaHDR" }))
        XCTAssertEqual(msaa.samples, 4)
        XCTAssertGreaterThan(try XCTUnwrap(msaa.pixel(x: 32, y: 32, sample: 1)).x, 0.1)
        let objects = try XCTUnwrap(forward.buffers.first(where: { $0.name == "Objects" }))
        XCTAssertEqual(objects.stride, 144)
        XCTAssertEqual(objects.bytes.count, 144)
        XCTAssertEqual(forward.buffers.first(where: { $0.name == "Frame uniforms" })?.bytes.count, 112)
        XCTAssertNotNil(forward.buffers.first(where: { $0.name.hasPrefix("Mesh ") }))
        let output = try XCTUnwrap(capture.passes[1].textures.first(where: { $0.name == "surface" }))
        let pixel = try XCTUnwrap(output.pixel(x: 32, y: 32))
        let saved = output.bytes
        XCTAssertGreaterThan(pixel.x, pixel.z)
        let profile = try XCTUnwrap(renderer.profiles.frames.last)
        XCTAssertEqual(profile.drawCount, 2)
        XCTAssertEqual(profile.passesGPU.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(profile.gpuMilliseconds), 0)
        XCTAssertTrue(profile.instrumented)
        config.exposure = 0.1
        snapshot.objects = []
        try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
        try renderer.waitUntilIdle()
        XCTAssertEqual(output.bytes, saved)
        let encoded = try capture.exportJSON()
        let roundtrip = try JSONDecoder.isoDates.decode(FrameCapture.self, from: encoded)
        XCTAssertEqual(roundtrip.passes[0].buffers[0].bytes, capture.passes[0].buffers[0].bytes)
        XCTAssertFalse(renderer.captureRequested)
    }
}

@MainActor private final class InstrumentedForwardPass: RenderPass {
    private let forward = ForwardPass()
    private var buffer: (any MTLBuffer)?
    private(set) var preparations = 0
    private(set) var framePreparations = 0

    func declaration(configuration: EngineConfiguration) -> PassDeclaration {
        forward.declaration(configuration: configuration)
    }

    func prepare(_ context: PassPreparationContext) throws {
        preparations += 1
        try forward.prepare(context)
        if buffer == nil {
            buffer = context.metal.device.makeBuffer(length: 16, options: .storageModeShared)
            buffer?.contents().initializeMemory(as: UInt8.self, repeating: 7, count: 16)
        }
    }

    func prepareFrame(_ context: PassContext) throws {
        framePreparations += 1
        let buffer = try XCTUnwrap(buffer)
        context.frame.useResource(buffer)
        if context.frame.isCapturing {
            context.frame.inspectBuffer("Custom pass data", buffer: buffer)
        }
    }

    func encode(_ context: PassContext) throws {
        try forward.encode(context)
    }
}

@MainActor private final class RejectMSAAOutputPass: RenderPass {
    private let output = OutputPass()

    func declaration(configuration: EngineConfiguration) -> PassDeclaration {
        output.declaration(configuration: configuration)
    }

    func prepare(_ context: PassPreparationContext) throws {
        guard context.configuration.sampleCount == 1 else {
            throw EngineError.invalidPipeline("Test preparation failure")
        }
        try output.prepare(context)
    }

    func encode(_ context: PassContext) throws {
        try output.encode(context)
    }
}

extension JSONDecoder {
    fileprivate static var isoDates: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension MetalTests {
    func testNativeGPUTraceWritesXcodeDocument() throws {
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
            throw XCTSkip("Metal 4 required")
        }

        guard MTLCaptureManager.shared().supportsDestination(.gpuTraceDocument) else {
            throw XCTSkip("Launch with MTL_CAPTURE_ENABLED=1 for native capture")
        }

        let url = FileManager.default.temporaryDirectory.appending(
            path: "GraphicsEngine-\(UUID().uuidString).gputrace")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let renderer = try MetalRenderer()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 32, height: 32, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let surface = try XCTUnwrap(renderer.metal.device.makeTexture(descriptor: descriptor))
        try renderer.requestGPUTrace(url: url)
        try renderer.render(
            snapshot: RenderSnapshot(), configuration: EngineConfiguration(), surface: surface)
        var directory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &directory))

        if directory.boolValue {
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty)
        } else {
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 1024)
        }

        XCTAssertFalse(MTLCaptureManager.shared().isCapturing)
    }
}
