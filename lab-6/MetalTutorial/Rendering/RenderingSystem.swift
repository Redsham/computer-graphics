import Metal
import MetalKit
import simd

// CPU-side draw packet for the geometry pass.
struct GeometryDrawCall {
    var vertexBuffer: MTLBuffer
    var vertexBufferOffset: Int
    var indexBuffer: MTLBuffer
    var indexBufferOffset: Int
    var indexCount: Int
    var indexType: MTLIndexType
    var primitiveType: MTLPrimitiveType
    var modelMatrix: simd_float4x4
    var albedoTexture: MTLTexture?
    var specularStrength: Float
}

// GPU-compatible directional light layout (matches shader struct).
struct MtlDirectionalLight {
    var direction: simd_float4
    var colorIntensity: simd_float4

    init(direction: simd_float3, color: simd_float3, intensity: Float) {
        self.direction = simd_float4(direction, 0)
        self.colorIntensity = simd_float4(color, intensity)
    }
}

// GPU-compatible point light layout.
struct MtlPointLight {
    var positionRadius: simd_float4
    var colorIntensity: simd_float4

    init(position: simd_float3, color: simd_float3, intensity: Float, radius: Float) {
        self.positionRadius = simd_float4(position, radius)
        self.colorIntensity = simd_float4(color, intensity)
    }
}

// GPU-compatible spot light layout.
struct MtlSpotLight {
    var positionRadius: simd_float4
    var directionInnerCos: simd_float4
    var colorIntensity: simd_float4
    var params: simd_float4

    init(position: simd_float3, direction: simd_float3, color: simd_float3, intensity: Float, innerCos: Float, outerCos: Float, radius: Float) {
        self.positionRadius = simd_float4(position, radius)
        self.directionInnerCos = simd_float4(direction, innerCos)
        self.colorIntensity = simd_float4(color, intensity)
        self.params = simd_float4(outerCos, 0, 0, 0)
    }
}

// Owns deferred resources/pipelines and records the two main passes.
final class RenderingSystem {
    enum DebugPreviewMode: Int32 {
        case lit = 0
        case albedo = 1
        case normal = 2
        case depth = 3
        case worldPosition = 4
    }

    private let device: MTLDevice
    private let library: MTLLibrary
    private let gbuffer: GBuffer

    private let geometryPSO: MTLRenderPipelineState
    private let lightingPSO: MTLRenderPipelineState

    private let depthStateGeometry: MTLDepthStencilState
    private let depthStateLighting: MTLDepthStencilState

    private let vertexDescriptor: MTLVertexDescriptor
    private var debugPreviewMode: DebugPreviewMode = .lit

    init(device: MTLDevice, view: MTKView) {
        self.device = device
        self.library = device.makeDefaultLibrary()!
        self.gbuffer = GBuffer(device: device, size: view.drawableSize)

        self.vertexDescriptor = Self.makeGeometryVertexDescriptor()

        // Create pass-specific pipeline states.
        self.geometryPSO = RenderingSystem.buildGeometryPSO(device: device, library: library, vertexDescriptor: vertexDescriptor)
        self.lightingPSO = RenderingSystem.buildLightingPSO(device: device, library: library, view: view)
        // Depth settings differ by pass: geometry writes depth, lighting ignores it.
        self.depthStateGeometry = RenderingSystem.buildDepthState(device: device, compare: .less, write: true)
        self.depthStateLighting = RenderingSystem.buildDepthState(device: device, compare: .always, write: false)
    }

    func resize(viewSize: CGSize) { gbuffer.resize(to: viewSize) }

    func setDebugPreviewMode(_ mode: DebugPreviewMode) {
        debugPreviewMode = mode
    }

    func encodeGeometryPass(commandBuffer: MTLCommandBuffer,
                            drawCalls: [GeometryDrawCall],
                            viewMatrix: simd_float4x4,
                            projectionMatrix: simd_float4x4) {
        // Pass 1 (deferred): rasterize scene into G-Buffer targets.
        let descriptor = gbuffer.makeGeometryPassDescriptor(clearColor: MTLClearColorMake(0, 0, 0, 1))
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "GeometryPass"
        encoder.setRenderPipelineState(geometryPSO)
        encoder.setDepthStencilState(depthStateGeometry)

        var view = viewMatrix
        var projection = projectionMatrix
        encoder.setVertexBytes(&view, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride, index: 3)

        // Encode every mesh/material packet.
        for drawCall in drawCalls {
            var model = drawCall.modelMatrix
            encoder.setVertexBytes(&model, length: MemoryLayout<simd_float4x4>.stride, index: 1)
            encoder.setVertexBuffer(drawCall.vertexBuffer, offset: drawCall.vertexBufferOffset, index: 0)
            var specularStrength = drawCall.specularStrength
            encoder.setFragmentBytes(&specularStrength, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setFragmentTexture(drawCall.albedoTexture, index: 0)
            encoder.drawIndexedPrimitives(type: drawCall.primitiveType,
                                          indexCount: drawCall.indexCount,
                                          indexType: drawCall.indexType,
                                          indexBuffer: drawCall.indexBuffer,
                                          indexBufferOffset: drawCall.indexBufferOffset)
        }

        encoder.endEncoding()
    }

    func encodeLightingPass(commandBuffer: MTLCommandBuffer,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            viewPosition: simd_float3,
                            directional: MtlDirectionalLight,
                            points: [MtlPointLight],
                            spots: [MtlSpotLight],
                            inverseView: simd_float4x4,
                            inverseProjection: simd_float4x4) {
        // Pass 2 (deferred): fullscreen resolve from G-Buffer + lights to final color.
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "LightingPass"
        encoder.setRenderPipelineState(lightingPSO)
        encoder.setDepthStencilState(depthStateLighting)

        // Bind G-Buffer attachments as read-only shader inputs.
        encoder.setFragmentTexture(gbuffer.albedo, index: 0)
        encoder.setFragmentTexture(gbuffer.normal, index: 1)
        encoder.setFragmentTexture(gbuffer.depth, index: 2)

        var eye = viewPosition
        var dirLight = directional
        var pointCount = UInt32(points.count)
        var spotCount = UInt32(spots.count)
        var invView = inverseView
        var invProj = inverseProjection
        var previewMode = debugPreviewMode.rawValue

        encoder.setFragmentBytes(&eye, length: MemoryLayout<simd_float3>.stride, index: 0)
        encoder.setFragmentBytes(&dirLight, length: MemoryLayout<MtlDirectionalLight>.stride, index: 1)
        encoder.setFragmentBytes(&pointCount, length: MemoryLayout<UInt32>.stride, index: 2)
        if !points.isEmpty {
            encoder.setFragmentBytes(points, length: MemoryLayout<MtlPointLight>.stride * points.count, index: 3)
        }

        encoder.setFragmentBytes(&spotCount, length: MemoryLayout<UInt32>.stride, index: 4)
        if !spots.isEmpty {
            encoder.setFragmentBytes(spots, length: MemoryLayout<MtlSpotLight>.stride * spots.count, index: 5)
        }

        encoder.setFragmentBytes(&invView, length: MemoryLayout<simd_float4x4>.stride, index: 6)
        encoder.setFragmentBytes(&invProj, length: MemoryLayout<simd_float4x4>.stride, index: 7)
        encoder.setFragmentBytes(&previewMode, length: MemoryLayout<Int32>.stride, index: 8)

        // Fullscreen single-triangle draw avoids seam issues and minimizes setup.
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    static func makeGeometryVertexDescriptor() -> MTLVertexDescriptor {
        // Vertex layout: position, uv, normal (single interleaved buffer).
        let descriptor = MTLVertexDescriptor()
        descriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stepFunction = .perVertex

        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0

        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = MemoryLayout<simd_float3>.stride + MemoryLayout<simd_float3>.stride
        descriptor.attributes[1].bufferIndex = 0

        descriptor.attributes[2].format = .float3
        descriptor.attributes[2].offset = MemoryLayout<simd_float3>.stride
        descriptor.attributes[2].bufferIndex = 0
        return descriptor
    }

    private static func buildGeometryPSO(device: MTLDevice, library: MTLLibrary, vertexDescriptor: MTLVertexDescriptor) -> MTLRenderPipelineState {
        // MRT output for deferred geometry: color(0)=albedo/spec, color(1)=normal.
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "GeometryPSO"
        descriptor.vertexFunction = library.makeFunction(name: "vertexGeometry")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentGeometry")
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[1].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func buildLightingPSO(device: MTLDevice, library: MTLLibrary, view: MTKView) -> MTLRenderPipelineState {
        // Lighting pipeline writes directly to the swapchain color target.
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "LightingPSO"
        descriptor.vertexFunction = library.makeFunction(name: "vertexFullscreen")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentLighting")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        return try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func buildDepthState(device: MTLDevice, compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState {
        // Small helper to build depth behavior per pass.
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = compare
        descriptor.isDepthWriteEnabled = write
        return device.makeDepthStencilState(descriptor: descriptor)!
    }
}
