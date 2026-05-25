import Metal
import MetalKit
import simd

private struct Particle {
    var positionSeed: simd_float4
    var velocityDrag: simd_float4
    var color: simd_float4
    var ageLifeSizeRandom: simd_float4
}

private struct ParticleUniforms {
    var emitterPosition: simd_float4
    var emitterDirection: simd_float4
    var emitterRight: simd_float4
    var emitterUp: simd_float4
    var cameraRight: simd_float4
    var cameraUp: simd_float4
    var timing: simd_float4
    var shape: simd_float4
    var velocity: simd_float4
    var lifeSize: simd_float4
    var behavior: simd_float4
    var colorStart: simd_float4
    var colorMid: simd_float4
    var colorEnd: simd_float4
    var fade: simd_float4
}

private struct ParticleSortKey {
    var depth: Float
    var particleIndex: UInt32
}

private struct ParticleCollisionUniforms {
    var viewProjection: simd_float4x4
    var inverseViewProjection: simd_float4x4
    var uvTransform: simd_float4
    var params: simd_float4
    var planeCenter: simd_float4
    var planeNormal: simd_float4
    var planeTangent: simd_float4
    var planeBitangent: simd_float4
    var planeParams: simd_float4
}

private struct SortParams {
    var stage: UInt32
    var pass: UInt32
    var count: UInt32
    var padding: UInt32 = 0
}

enum ParticleBlendMode {
    case alpha
    case additive
}

struct RocketEngineCollisionPlane {
    var center: simd_float3
    var normal: simd_float3
    var tangent: simd_float3
    var bitangent: simd_float3
    var halfExtents: simd_float2
}

struct ParticleEmitterSettings {
    var position: simd_float3
    var direction: simd_float3
    var activeFractionRange: simd_float2
    var radiusRange: simd_float2
    var coneSpreadRange: simd_float2
    var speedRange: simd_float2
    var dragRange: simd_float2
    var lifeRange: simd_float2
    var sizeRange: simd_float2
    var growthRate: Float
    var turbulence: Float
    var axialAcceleration: Float
    var stretch: Float
    var colorStart: simd_float4
    var colorMid: simd_float4
    var colorEnd: simd_float4
    var fadeInFraction: Float
    var fadeOutStartFraction: Float
    var alphaScale: Float
    var collisionThreshold: Float
    var collisionDamping: Float
    var collisionAgeBoost: Float
    var collisionPlaneCenter: simd_float3 = .zero
    var collisionPlaneNormal: simd_float3 = simd_float3(1.0, 0.0, 0.0)
    var collisionPlaneTangent: simd_float3 = simd_float3(0.0, 1.0, 0.0)
    var collisionPlaneBitangent: simd_float3 = simd_float3(0.0, 0.0, 1.0)
    var collisionPlaneHalfExtents: simd_float2 = .zero
    var collisionPlaneEnabled: Float = 0.0
}

final class ParticleSystem {
    private let maxParticleCount: Int
    private let sortKeyCount: Int
    private let particleBuffer: MTLBuffer
    private let sortKeyBuffer: MTLBuffer
    private let liveCounterBuffer: MTLBuffer
    private let computePipeline: MTLComputePipelineState
    private let sortKeyPipeline: MTLComputePipelineState
    private let sortPipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private(set) var latestLiveCount: UInt32 = 0
    private let label: String

    init(device: MTLDevice,
         view: MTKView,
         maxParticleCount: Int,
         blendMode: ParticleBlendMode,
         label: String = "ParticleSystem") {
        self.maxParticleCount = maxParticleCount
        self.sortKeyCount = Self.nextPowerOfTwo(maxParticleCount)
        self.label = label

        let library = device.makeDefaultLibrary()!
        self.computePipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "updateParticlePool")!
        )
        self.sortKeyPipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "buildParticleSortKeys")!
        )
        self.sortPipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "sortParticleKeys")!
        )
        self.renderPipeline = Self.buildRenderPipeline(
            device: device,
            library: library,
            view: view,
            blendMode: blendMode,
            label: label
        )
        self.depthState = Self.buildDepthState(device: device)

        let particleBufferLength = MemoryLayout<Particle>.stride * maxParticleCount
        let sortKeyBufferLength = MemoryLayout<ParticleSortKey>.stride * sortKeyCount
        self.particleBuffer = device.makeBuffer(length: particleBufferLength, options: .storageModeShared)!
        self.sortKeyBuffer = device.makeBuffer(length: sortKeyBufferLength, options: .storageModeShared)!
        self.liveCounterBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!

        memset(particleBuffer.contents(), 0, particleBufferLength)
        memset(sortKeyBuffer.contents(), 0, sortKeyBufferLength)
        memset(liveCounterBuffer.contents(), 0, MemoryLayout<UInt32>.stride)
    }

    func encode(commandBuffer: MTLCommandBuffer,
                drawableTexture: MTLTexture,
                depthTexture: MTLTexture,
                viewMatrix: simd_float4x4,
                projectionMatrix: simd_float4x4,
                time: Float,
                deltaTime: Float,
                intensity: Float,
                settings: ParticleEmitterSettings,
                renderViewport: RenderViewport? = nil) {
        var uniforms = makeUniforms(
            settings: settings,
            viewMatrix: viewMatrix,
            time: time,
            deltaTime: deltaTime,
            intensity: intensity
        )

        clearLiveCounter(commandBuffer: commandBuffer)
        var collision = makeCollisionUniforms(
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            settings: settings,
            renderViewport: renderViewport
        )
        updateParticles(
            commandBuffer: commandBuffer,
            depthTexture: depthTexture,
            uniforms: &uniforms,
            collision: &collision
        )
        buildSortKeys(commandBuffer: commandBuffer, uniforms: &uniforms, viewMatrix: viewMatrix)
        sortParticles(commandBuffer: commandBuffer)
        renderParticles(
            commandBuffer: commandBuffer,
            drawableTexture: drawableTexture,
            depthTexture: depthTexture,
            uniforms: &uniforms,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            renderViewport: renderViewport
        )
        updateLiveCountAfterCompletion(commandBuffer: commandBuffer)
    }

    private func makeUniforms(settings: ParticleEmitterSettings,
                              viewMatrix: simd_float4x4,
                              time: Float,
                              deltaTime: Float,
                              intensity: Float) -> ParticleUniforms {
        let clampedIntensity = max(0.0, min(1.0, intensity))
        let directionLength = max(simd_length(settings.direction), 0.0001)
        let direction = settings.direction / directionLength
        let basis = makeEmitterBasis(direction: direction)

        let inverseView = viewMatrix.inverse
        let cameraRightColumn = inverseView.columns.0
        let cameraUpColumn = inverseView.columns.1
        let cameraRight = simd_normalize(simd_float3(cameraRightColumn.x, cameraRightColumn.y, cameraRightColumn.z))
        let cameraUp = simd_normalize(simd_float3(cameraUpColumn.x, cameraUpColumn.y, cameraUpColumn.z))
        let activeFraction = settings.activeFractionRange.x
            + (settings.activeFractionRange.y - settings.activeFractionRange.x) * clampedIntensity

        return ParticleUniforms(
            emitterPosition: simd_float4(settings.position, 1.0),
            emitterDirection: simd_float4(direction, 0.0),
            emitterRight: simd_float4(basis.right, 0.0),
            emitterUp: simd_float4(basis.up, 0.0),
            cameraRight: simd_float4(cameraRight, 0.0),
            cameraUp: simd_float4(cameraUp, 0.0),
            timing: simd_float4(deltaTime, time, clampedIntensity, Float(maxParticleCount)),
            shape: simd_float4(
                settings.radiusRange.x,
                settings.radiusRange.y,
                settings.coneSpreadRange.x + (settings.coneSpreadRange.y - settings.coneSpreadRange.x) * clampedIntensity,
                activeFraction
            ),
            velocity: simd_float4(settings.speedRange.x, settings.speedRange.y, settings.dragRange.x, settings.dragRange.y),
            lifeSize: simd_float4(settings.lifeRange.x, settings.lifeRange.y, settings.sizeRange.x, settings.sizeRange.y),
            behavior: simd_float4(settings.growthRate, settings.turbulence, settings.axialAcceleration, settings.stretch),
            colorStart: settings.colorStart,
            colorMid: settings.colorMid,
            colorEnd: settings.colorEnd,
            fade: simd_float4(settings.fadeInFraction, settings.fadeOutStartFraction, settings.alphaScale, 0.0)
        )
    }

    private func makeEmitterBasis(direction: simd_float3) -> (right: simd_float3, up: simd_float3) {
        let helper = abs(simd_dot(direction, simd_float3(0.0, 1.0, 0.0))) > 0.92
            ? simd_float3(1.0, 0.0, 0.0)
            : simd_float3(0.0, 1.0, 0.0)
        let right = simd_normalize(simd_cross(helper, direction))
        let up = simd_normalize(simd_cross(direction, right))
        return (right, up)
    }

    private func clearLiveCounter(commandBuffer: MTLCommandBuffer) {
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
        blitEncoder.label = "\(label) Live Counter Clear"
        blitEncoder.fill(buffer: liveCounterBuffer, range: 0 ..< MemoryLayout<UInt32>.stride, value: 0)
        blitEncoder.endEncoding()
    }

    private func makeCollisionUniforms(viewMatrix: simd_float4x4,
                                       projectionMatrix: simd_float4x4,
                                       settings: ParticleEmitterSettings,
                                       renderViewport: RenderViewport?) -> ParticleCollisionUniforms {
        ParticleCollisionUniforms(
            viewProjection: projectionMatrix * viewMatrix,
            inverseViewProjection: (projectionMatrix * viewMatrix).inverse,
            uvTransform: renderViewport?.gBufferUVTransform ?? simd_float4(1.0, 1.0, 0.0, 0.0),
            params: simd_float4(
                settings.collisionThreshold,
                settings.collisionDamping,
                settings.collisionAgeBoost,
                1.0
            ),
            planeCenter: simd_float4(settings.collisionPlaneCenter, 1.0),
            planeNormal: simd_float4(simd_normalize(settings.collisionPlaneNormal), 0.0),
            planeTangent: simd_float4(simd_normalize(settings.collisionPlaneTangent), 0.0),
            planeBitangent: simd_float4(simd_normalize(settings.collisionPlaneBitangent), 0.0),
            planeParams: simd_float4(
                settings.collisionPlaneHalfExtents.x,
                settings.collisionPlaneHalfExtents.y,
                settings.collisionDamping,
                settings.collisionPlaneEnabled
            )
        )
    }

    private func updateParticles(commandBuffer: MTLCommandBuffer,
                                 depthTexture: MTLTexture,
                                 uniforms: inout ParticleUniforms,
                                 collision: inout ParticleCollisionUniforms) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "\(label) Compute"
        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(liveCounterBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
        encoder.setBytes(&collision, length: MemoryLayout<ParticleCollisionUniforms>.stride, index: 3)
        encoder.setTexture(depthTexture, index: 0)

        let threadsPerThreadgroup = MTLSize(width: computePipeline.threadExecutionWidth, height: 1, depth: 1)
        let threadCount = MTLSize(width: maxParticleCount, height: 1, depth: 1)
        encoder.dispatchThreads(threadCount, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }

    private func buildSortKeys(commandBuffer: MTLCommandBuffer,
                               uniforms: inout ParticleUniforms,
                               viewMatrix: simd_float4x4) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "\(label) Build Sort Keys"
        encoder.setComputePipelineState(sortKeyPipeline)
        var view = viewMatrix
        var keyCount = UInt32(sortKeyCount)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(sortKeyBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
        encoder.setBytes(&view, length: MemoryLayout<simd_float4x4>.stride, index: 3)
        encoder.setBytes(&keyCount, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadsPerThreadgroup = MTLSize(width: sortKeyPipeline.threadExecutionWidth, height: 1, depth: 1)
        let threadCount = MTLSize(width: sortKeyCount, height: 1, depth: 1)
        encoder.dispatchThreads(threadCount, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }

    private func sortParticles(commandBuffer: MTLCommandBuffer) {
        var stage = 2
        while stage <= sortKeyCount {
            var pass = stage / 2
            while pass > 0 {
                guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
                encoder.label = "\(label) GPU Sort"
                encoder.setComputePipelineState(sortPipeline)
                var params = SortParams(stage: UInt32(stage), pass: UInt32(pass), count: UInt32(sortKeyCount))
                encoder.setBuffer(sortKeyBuffer, offset: 0, index: 0)
                encoder.setBytes(&params, length: MemoryLayout<SortParams>.stride, index: 1)

                let threadsPerThreadgroup = MTLSize(width: sortPipeline.threadExecutionWidth, height: 1, depth: 1)
                let threadCount = MTLSize(width: sortKeyCount, height: 1, depth: 1)
                encoder.dispatchThreads(threadCount, threadsPerThreadgroup: threadsPerThreadgroup)
                encoder.endEncoding()
                pass /= 2
            }
            stage *= 2
        }
    }

    private func renderParticles(commandBuffer: MTLCommandBuffer,
                                 drawableTexture: MTLTexture,
                                 depthTexture: MTLTexture,
                                 uniforms: inout ParticleUniforms,
                                 viewMatrix: simd_float4x4,
                                 projectionMatrix: simd_float4x4,
                                 renderViewport: RenderViewport?) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawableTexture
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .load
        descriptor.depthAttachment.storeAction = .dontCare

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "\(label) Render"
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        apply(renderViewport: renderViewport, encoder: encoder)

        var view = viewMatrix
        var projection = projectionMatrix
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(sortKeyBuffer, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
        encoder.setVertexBytes(&view, length: MemoryLayout<simd_float4x4>.stride, index: 3)
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride, index: 4)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: maxParticleCount)
        encoder.endEncoding()
    }

    private func updateLiveCountAfterCompletion(commandBuffer: MTLCommandBuffer) {
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let rawCount = self.liveCounterBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee
            self.latestLiveCount = min(rawCount, UInt32(self.maxParticleCount))
        }
    }

    private func apply(renderViewport: RenderViewport?, encoder: MTLRenderCommandEncoder) {
        guard let renderViewport else { return }
        encoder.setViewport(renderViewport.viewport)
        encoder.setScissorRect(renderViewport.scissorRect)
    }

    private static func buildRenderPipeline(device: MTLDevice,
                                            library: MTLLibrary,
                                            view: MTKView,
                                            blendMode: ParticleBlendMode,
                                            label: String) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "\(label) PSO"
        descriptor.vertexFunction = library.makeFunction(name: "vertexParticle")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentParticle")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        switch blendMode {
        case .alpha:
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .additive:
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        }
        return try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func buildDepthState(device: MTLDevice) -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = false
        return device.makeDepthStencilState(descriptor: descriptor)!
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int {
        var power = 1
        while power < value {
            power <<= 1
        }
        return power
    }
}

final class RocketEngineParticleEffect {
    private let fireSystem: ParticleSystem
    private let smokeSystem: ParticleSystem

    var debugStatus: String {
        "Particles F/S: \(fireSystem.latestLiveCount)/\(smokeSystem.latestLiveCount)"
    }

    init(device: MTLDevice, view: MTKView) {
        self.fireSystem = ParticleSystem(device: device, view: view, maxParticleCount: 2048, blendMode: .additive, label: "Rocket Fire")
        self.smokeSystem = ParticleSystem(device: device, view: view, maxParticleCount: 4096, blendMode: .alpha, label: "Rocket Smoke")
    }

    func encode(commandBuffer: MTLCommandBuffer,
                drawableTexture: MTLTexture,
                depthTexture: MTLTexture,
                emitterPosition: simd_float3,
                exhaustDirection: simd_float3,
                collisionPlane: RocketEngineCollisionPlane?,
                viewMatrix: simd_float4x4,
                projectionMatrix: simd_float4x4,
                time: Float,
                deltaTime: Float,
                throttle: Float,
                renderViewport: RenderViewport? = nil) {
        let smoke = ParticleEmitterSettings(
            position: emitterPosition + exhaustDirection * 48.0,
            direction: exhaustDirection,
            activeFractionRange: simd_float2(0.20, 0.95),
            radiusRange: simd_float2(3.0, 14.0),
            coneSpreadRange: simd_float2(0.05, 0.15),
            speedRange: simd_float2(800.0, 1000.0),
            dragRange: simd_float2(0.8, 1.2),
            lifeRange: simd_float2(2.5, 3.0),
            sizeRange: simd_float2(5.0, 12.0),
            growthRate: 1.65,
            turbulence: 100.0,
            axialAcceleration: -30.0,
            stretch: 1.0,
            colorStart: simd_float4(0.28, 0.23, 0.18, 0.20),
            colorMid: simd_float4(0.43, 0.42, 0.39, 0.15),
            colorEnd: simd_float4(0.18, 0.18, 0.19, 0.0),
            fadeInFraction: 0.08,
            fadeOutStartFraction: 0.38,
            alphaScale: 0.30,
            collisionThreshold: 0.00008,
            collisionDamping: 0.04,
            collisionAgeBoost: 2.0,
            collisionPlaneCenter: collisionPlane?.center ?? .zero,
            collisionPlaneNormal: collisionPlane?.normal ?? simd_float3(1.0, 0.0, 0.0),
            collisionPlaneTangent: collisionPlane?.tangent ?? simd_float3(0.0, 1.0, 0.0),
            collisionPlaneBitangent: collisionPlane?.bitangent ?? simd_float3(0.0, 0.0, 1.0),
            collisionPlaneHalfExtents: collisionPlane?.halfExtents ?? .zero,
            collisionPlaneEnabled: collisionPlane == nil ? 0.0 : 1.0
        )
        let fire = ParticleEmitterSettings(
            position: emitterPosition,
            direction: exhaustDirection,
            activeFractionRange: simd_float2(0.35, 1.0),
            radiusRange: simd_float2(0.5, 3.8),
            coneSpreadRange: simd_float2(0.025, 0.095),
            speedRange: simd_float2(800.0, 1200.0),
            dragRange: simd_float2(0.03, 0.12),
            lifeRange: simd_float2(0.3, 0.5),
            sizeRange: simd_float2(1.4, 3.8),
            growthRate: 0.60,
            turbulence: 10.0,
            axialAcceleration: 80.0,
            stretch: 20.0,
            colorStart: simd_float4(1.0, 0.98, 0.78, 0.70),
            colorMid: simd_float4(1.0, 0.2, 0.07, 0.48),
            colorEnd: simd_float4(0.42, 0.03, 0.0, 0.0),
            fadeInFraction: 0.0,
            fadeOutStartFraction: 0.36,
            alphaScale: 0.82,
            collisionThreshold: 0.00008,
            collisionDamping: 0.02,
            collisionAgeBoost: 24.0,
            collisionPlaneCenter: collisionPlane?.center ?? .zero,
            collisionPlaneNormal: collisionPlane?.normal ?? simd_float3(1.0, 0.0, 0.0),
            collisionPlaneTangent: collisionPlane?.tangent ?? simd_float3(0.0, 1.0, 0.0),
            collisionPlaneBitangent: collisionPlane?.bitangent ?? simd_float3(0.0, 0.0, 1.0),
            collisionPlaneHalfExtents: collisionPlane?.halfExtents ?? .zero,
            collisionPlaneEnabled: collisionPlane == nil ? 0.0 : 1.0
        )

        smokeSystem.encode(
            commandBuffer: commandBuffer,
            drawableTexture: drawableTexture,
            depthTexture: depthTexture,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            time: time,
            deltaTime: deltaTime,
            intensity: throttle,
            settings: smoke,
            renderViewport: renderViewport
        )
        fireSystem.encode(
            commandBuffer: commandBuffer,
            drawableTexture: drawableTexture,
            depthTexture: depthTexture,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            time: time,
            deltaTime: deltaTime,
            intensity: throttle,
            settings: fire,
            renderViewport: renderViewport
        )
    }
}
