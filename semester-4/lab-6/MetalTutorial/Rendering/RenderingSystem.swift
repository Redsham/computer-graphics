import Metal
import MetalKit
import simd

struct MaterialDrawState {
    var albedoTexture: MTLTexture?
    var normalTexture: MTLTexture?
    var displacementTexture: MTLTexture?
    var specularStrength: Float
}

struct IndexedGeometryDrawCall {
    var vertexBuffer: MTLBuffer
    var vertexBufferOffset: Int
    var indexBuffer: MTLBuffer
    var indexBufferOffset: Int
    var indexCount: Int
    var indexType: MTLIndexType
    var primitiveType: MTLPrimitiveType
    var modelMatrix: simd_float4x4
    var material: MaterialDrawState
}

struct TessellatedGeometryDrawCall {
    var controlPointBuffer: MTLBuffer
    var patchInfoBuffer: MTLBuffer
    var tessellationFactorBuffer: MTLBuffer
    var patchCount: Int
    var modelMatrix: simd_float4x4
    var displacementScale: Float
    var uvScale: simd_float2
    var normalStrength: Float
    var material: MaterialDrawState
}

enum GeometryDrawCall {
    case indexed(IndexedGeometryDrawCall)
    case tessellated(TessellatedGeometryDrawCall)
}

enum GeometryRendererKind {
    case deferredIndexed
    case tessellatedTerrain
}

struct TessellationPatchInfo {
    var patchCenter: simd_float3
    var minFactor: Float
    var maxFactor: Float
    var minDistance: Float
    var maxDistance: Float
    var edgeMidpoint0: simd_float3
    var edgeMidpoint1: simd_float3
    var edgeMidpoint2: simd_float3
    var edgeMidpoint3: simd_float3
}

struct TessellationSurfaceParams {
    var displacementScale: Float
    var uvScale: simd_float2
    var normalStrength: Float
    var _padding: Float
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

struct MtlAmbientLight {
    var colorIntensity: simd_float4

    init(color: simd_float3, intensity: Float) {
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
        case wireframe = 5
    }

    private let device: MTLDevice
    private let library: MTLLibrary
    private let gbuffer: GBuffer

    private let indexedGeometryPSO: MTLRenderPipelineState
    private let tessellationGeometryPSO: MTLRenderPipelineState
    private let lightingPSO: MTLRenderPipelineState
    private let tessellationFactorCSO: MTLComputePipelineState

    private let depthStateGeometry: MTLDepthStencilState
    private let depthStateLighting: MTLDepthStencilState

    private let vertexDescriptor: MTLVertexDescriptor
    private let fallbackAlbedoTexture: MTLTexture
    private let fallbackNormalTexture: MTLTexture
    private let fallbackDisplacementTexture: MTLTexture
    private var debugPreviewMode: DebugPreviewMode = .lit

    init(device: MTLDevice, view: MTKView) {
        self.device = device
        self.library = device.makeDefaultLibrary()!
        self.gbuffer = GBuffer(device: device, size: view.drawableSize)

        self.vertexDescriptor = Self.makeGeometryVertexDescriptor()
        self.fallbackAlbedoTexture = RenderingSystem.makeFallbackTexture(
            device: device,
            pixelFormat: .rgba8Unorm,
            bytes: [255, 255, 255, 255]
        )
        self.fallbackNormalTexture = RenderingSystem.makeFallbackTexture(
            device: device,
            pixelFormat: .rgba8Unorm,
            bytes: [128, 128, 255, 255]
        )
        self.fallbackDisplacementTexture = RenderingSystem.makeFallbackTexture(
            device: device,
            pixelFormat: .r8Unorm,
            bytes: [128]
        )

        // Create pass-specific pipeline states.
        self.indexedGeometryPSO = RenderingSystem.buildIndexedGeometryPSO(device: device, library: library, vertexDescriptor: vertexDescriptor)
        self.tessellationGeometryPSO = RenderingSystem.buildTessellationGeometryPSO(device: device, library: library)
        self.lightingPSO = RenderingSystem.buildLightingPSO(device: device, library: library, view: view)
        self.tessellationFactorCSO = RenderingSystem.buildTessellationFactorCSO(device: device, library: library)
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
                            rendererKind: GeometryRendererKind,
                            cameraPosition: simd_float3,
                            viewMatrix: simd_float4x4,
                            projectionMatrix: simd_float4x4) {
        if rendererKind == .tessellatedTerrain {
            encodeTessellationFactorPass(commandBuffer: commandBuffer,
                                         drawCalls: drawCalls,
                                         cameraPosition: cameraPosition)
        }

        // Pass 1 (deferred): rasterize scene into G-Buffer targets.
        let descriptor = gbuffer.makeGeometryPassDescriptor(clearColor: MTLClearColorMake(0, 0, 0, 1))
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "GeometryPass"
        encoder.setDepthStencilState(depthStateGeometry)

        switch rendererKind {
        case .deferredIndexed:
            encoder.setRenderPipelineState(indexedGeometryPSO)
            encoder.setCullMode(.back)
            encoder.setFrontFacing(.counterClockwise)
            if debugPreviewMode == .wireframe {
                encoder.setTriangleFillMode(.lines)
            }

            var view = viewMatrix
            var projection = projectionMatrix
            var camera = cameraPosition
            encoder.setVertexBytes(&view, length: MemoryLayout<simd_float4x4>.stride, index: 2)
            encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride, index: 3)
            encoder.setVertexBytes(&camera, length: MemoryLayout<simd_float3>.stride, index: 4)

            for drawCall in drawCalls {
                guard case let .indexed(indexedDrawCall) = drawCall else { continue }
                encodeIndexedGeometry(drawCall: indexedDrawCall, encoder: encoder)
            }

        case .tessellatedTerrain:
            encoder.setCullMode(.back)
            encoder.setFrontFacing(.clockwise)
            if debugPreviewMode == .wireframe {
                encoder.setTriangleFillMode(.lines)
            }
            encodeTessellatedGeometry(encoder: encoder,
                                      drawCalls: drawCalls,
                                      viewMatrix: viewMatrix,
                                      projectionMatrix: projectionMatrix)
        }

        encoder.endEncoding()
    }

    func encodeLightingPass(commandBuffer: MTLCommandBuffer,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            viewPosition: simd_float3,
                            ambient: MtlAmbientLight,
                            directional: MtlDirectionalLight,
                            points: [MtlPointLight],
                            spots: [MtlSpotLight],
                            inverseView: simd_float4x4,
                            inverseProjection: simd_float4x4) {
        // Pass 2 (deferred): fullscreen resolve from G-Buffer + lights to final color.
        let colorAttachment = renderPassDescriptor.colorAttachments[0]
        colorAttachment?.loadAction = .clear
        colorAttachment?.storeAction = .store
        renderPassDescriptor.depthAttachment.loadAction = .dontCare
        renderPassDescriptor.depthAttachment.storeAction = .dontCare

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "LightingPass"
        encoder.setRenderPipelineState(lightingPSO)
        encoder.setDepthStencilState(depthStateLighting)

        // Bind G-Buffer attachments as read-only shader inputs.
        encoder.setFragmentTexture(gbuffer.albedo, index: 0)
        encoder.setFragmentTexture(gbuffer.normal, index: 1)
        encoder.setFragmentTexture(gbuffer.depth, index: 2)

        var eye = viewPosition
        var ambientLight = ambient
        var dirLight = directional
        var pointCount = UInt32(points.count)
        var spotCount = UInt32(spots.count)
        var invView = inverseView
        var invProj = inverseProjection
        var previewMode = debugPreviewMode.rawValue

        encoder.setFragmentBytes(&eye, length: MemoryLayout<simd_float3>.stride, index: 0)
        encoder.setFragmentBytes(&ambientLight, length: MemoryLayout<MtlAmbientLight>.stride, index: 1)
        encoder.setFragmentBytes(&dirLight, length: MemoryLayout<MtlDirectionalLight>.stride, index: 2)
        encoder.setFragmentBytes(&pointCount, length: MemoryLayout<UInt32>.stride, index: 3)
        if points.isEmpty {
            var dummy = MtlPointLight(
                position: .zero,
                color: .zero,
                intensity: 0,
                radius: 0
            )
            encoder.setFragmentBytes(&dummy,
                length: MemoryLayout<MtlPointLight>.stride,
                index: 4)
        } else {
            encoder.setFragmentBytes(points,
                length: MemoryLayout<MtlPointLight>.stride * points.count,
                index: 4)
        }

        encoder.setFragmentBytes(&spotCount, length: MemoryLayout<UInt32>.stride, index: 5)
        if spots.isEmpty {
            var dummy = MtlSpotLight(
                position: .zero,
                direction: .zero,
                color: .zero,
                intensity: 0,
                innerCos: 0,
                outerCos: 0,
                radius: 0
            )

            encoder.setFragmentBytes(&dummy,
                length: MemoryLayout<MtlSpotLight>.stride,
                index: 6)
        } else {
            encoder.setFragmentBytes(spots,
                length: MemoryLayout<MtlSpotLight>.stride * spots.count,
                index: 6)
        }

        encoder.setFragmentBytes(&invView, length: MemoryLayout<simd_float4x4>.stride, index: 7)
        encoder.setFragmentBytes(&invProj, length: MemoryLayout<simd_float4x4>.stride, index: 8)
        encoder.setFragmentBytes(&previewMode, length: MemoryLayout<Int32>.stride, index: 9)

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

    private func encodeIndexedGeometry(drawCall: IndexedGeometryDrawCall,
                                       encoder: MTLRenderCommandEncoder) {
        var model = drawCall.modelMatrix
        var surfaceParams = simd_float2.zero
        encoder.setVertexBytes(&model, length: MemoryLayout<simd_float4x4>.stride, index: 1)
        encoder.setVertexBytes(&surfaceParams, length: MemoryLayout<simd_float2>.stride, index: 5)
        encoder.setVertexBuffer(drawCall.vertexBuffer, offset: drawCall.vertexBufferOffset, index: 0)

        var specularStrength = drawCall.material.specularStrength
        encoder.setFragmentBytes(&specularStrength, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentTexture(drawCall.material.albedoTexture ?? fallbackAlbedoTexture, index: 0)
        encoder.setFragmentTexture(drawCall.material.normalTexture ?? fallbackNormalTexture, index: 1)
        encoder.setVertexTexture(drawCall.material.displacementTexture ?? fallbackDisplacementTexture, index: 0)
        encoder.drawIndexedPrimitives(type: drawCall.primitiveType,
                                      indexCount: drawCall.indexCount,
                                      indexType: drawCall.indexType,
                                      indexBuffer: drawCall.indexBuffer,
                                      indexBufferOffset: drawCall.indexBufferOffset)
    }

    private func encodeTessellationFactorPass(commandBuffer: MTLCommandBuffer,
                                              drawCalls: [GeometryDrawCall],
                                              cameraPosition: simd_float3) {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        computeEncoder.label = "TessellationFactorPass"
        computeEncoder.setComputePipelineState(tessellationFactorCSO)

        var camera = cameraPosition
        computeEncoder.setBytes(&camera, length: MemoryLayout<simd_float3>.stride, index: 2)

        for drawCall in drawCalls {
            guard case let .tessellated(tessellatedDrawCall) = drawCall else { continue }

            computeEncoder.setBuffer(tessellatedDrawCall.patchInfoBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(tessellatedDrawCall.tessellationFactorBuffer, offset: 0, index: 1)

            let width = max(1, min(tessellationFactorCSO.threadExecutionWidth, tessellatedDrawCall.patchCount))
            let threadsPerThreadgroup = MTLSize(width: width, height: 1, depth: 1)
            let threadCount = MTLSize(width: tessellatedDrawCall.patchCount, height: 1, depth: 1)
            computeEncoder.dispatchThreads(threadCount, threadsPerThreadgroup: threadsPerThreadgroup)
        }

        computeEncoder.endEncoding()
    }

    private func encodeTessellatedGeometry(encoder: MTLRenderCommandEncoder,
                                           drawCalls: [GeometryDrawCall],
                                           viewMatrix: simd_float4x4,
                                           projectionMatrix: simd_float4x4) {
        encoder.setRenderPipelineState(tessellationGeometryPSO)

        var view = viewMatrix
        var projection = projectionMatrix
        encoder.setVertexBytes(&view, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride, index: 3)

        for drawCall in drawCalls {
            guard case let .tessellated(tessellatedDrawCall) = drawCall else { continue }

            var model = tessellatedDrawCall.modelMatrix
            var surfaceParams = TessellationSurfaceParams(
                displacementScale: tessellatedDrawCall.displacementScale,
                uvScale: tessellatedDrawCall.uvScale,
                normalStrength: tessellatedDrawCall.material.normalTexture == nil ? 0.0 : tessellatedDrawCall.normalStrength,
                _padding: 0.0
            )
            var specularStrength = tessellatedDrawCall.material.specularStrength

            encoder.setVertexBuffer(tessellatedDrawCall.controlPointBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&model, length: MemoryLayout<simd_float4x4>.stride, index: 1)
            encoder.setVertexBytes(&surfaceParams, length: MemoryLayout<TessellationSurfaceParams>.stride, index: 4)
            encoder.setVertexTexture(tessellatedDrawCall.material.displacementTexture ?? fallbackDisplacementTexture, index: 0)

            encoder.setFragmentBytes(&specularStrength, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setFragmentBytes(&surfaceParams, length: MemoryLayout<TessellationSurfaceParams>.stride, index: 1)
            encoder.setFragmentTexture(tessellatedDrawCall.material.albedoTexture ?? fallbackAlbedoTexture, index: 0)
            encoder.setFragmentTexture(tessellatedDrawCall.material.normalTexture ?? fallbackNormalTexture, index: 1)

            encoder.setTessellationFactorBuffer(tessellatedDrawCall.tessellationFactorBuffer, offset: 0, instanceStride: 0)
            encoder.drawPatches(
                numberOfPatchControlPoints: 4,
                patchStart: 0,
                patchCount: tessellatedDrawCall.patchCount,
                patchIndexBuffer: nil,
                patchIndexBufferOffset: 0,
                instanceCount: 1,
                baseInstance: 0
            )
        }
    }

    private static func buildIndexedGeometryPSO(device: MTLDevice, library: MTLLibrary, vertexDescriptor: MTLVertexDescriptor) -> MTLRenderPipelineState {
        // MRT output for deferred geometry: color(0)=albedo/spec, color(1)=normal.
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "IndexedGeometryPSO"
        descriptor.vertexFunction = library.makeFunction(name: "vertexGeometry")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentGeometry")
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[1].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func buildTessellationGeometryPSO(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "TessellationGeometryPSO"
        descriptor.vertexFunction = library.makeFunction(name: "vertexTerrainTessellated")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentTerrainGeometry")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[1].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.maxTessellationFactor = 32
        descriptor.isTessellationFactorScaleEnabled = false
        descriptor.tessellationFactorFormat = .half
        descriptor.tessellationControlPointIndexType = .none
        descriptor.tessellationFactorStepFunction = .constant
        descriptor.tessellationOutputWindingOrder = .counterClockwise
        descriptor.tessellationPartitionMode = .fractionalEven
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

    private static func buildTessellationFactorCSO(device: MTLDevice, library: MTLLibrary) -> MTLComputePipelineState {
        let function = library.makeFunction(name: "computeTerrainTessellationFactors")!
        return try! device.makeComputePipelineState(function: function)
    }

    private static func buildDepthState(device: MTLDevice, compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState {
        // Small helper to build depth behavior per pass.
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = compare
        descriptor.isDepthWriteEnabled = write
        return device.makeDepthStencilState(descriptor: descriptor)!
    }

    private static func makeFallbackTexture(device: MTLDevice,
                                            pixelFormat: MTLPixelFormat,
                                            bytes: [UInt8]) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        let texture = device.makeTexture(descriptor: descriptor)!
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytes.count
        )
        return texture
    }
}
