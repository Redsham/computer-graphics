import Metal
import MetalKit
import simd

// Top-level frame orchestrator:
// 1) updates camera and matrices,
// 2) records geometry pass into the G-Buffer,
// 3) records lighting pass that resolves final color to the swapchain.
final class Renderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let renderingSystem: RenderingSystem

    private var drawCalls: [GeometryDrawCall] = []

    // Camera state used to build view/projection matrices every frame.
    private var viewPosition = simd_float3(0.0, 4.0, 15.0)
    private var aspectRatio: Float = 1.0
    private var cameraController: CameraFlyController?

    // Scene light sets consumed during deferred lighting.
    private var dirLight: MtlDirectionalLight
    private var pointLights: [MtlPointLight]
    private var spotLights: [MtlSpotLight]

    init?(metalKitView: MTKView) {
        // Bootstrap Metal device/queue and configure drawable formats.
        guard let device = metalKitView.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        metalKitView.colorPixelFormat = .bgra8Unorm
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.sampleCount = 1

        self.renderingSystem = RenderingSystem(device: device, view: metalKitView)

        let (presetDirectional, presetPoints, presetSpots) = SceneLightRig.sponza()
        self.dirLight = presetDirectional
        self.pointLights = presetPoints
        self.spotLights = presetSpots

        super.init()

        // Build draw call list (USD scene or cube fallback).
        loadScene(device: device)
        metalKitView.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Keep camera projection and G-Buffer resolution in sync with the viewport.
        aspectRatio = Float(size.width / max(size.height, 1))
        renderingSystem.resize(viewSize: size)
    }

    func draw(in view: MTKView) {
        // Allocate per-frame command objects.
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }

        // Update camera movement and derive matrices.
        let deltaTime = max(Float(view.preferredFramesPerSecond > 0 ? 1.0 / Double(view.preferredFramesPerSecond) : 1.0 / 60.0), 1.0 / 240.0)
        cameraController?.update(deltaTime: deltaTime)

        let projection = createPerspectiveMatrix(
            fov: toRadians(from: 50.0),
            aspectRatio: aspectRatio,
            nearPlane: 0.05,
            farPlane: 50000.0
        )
        let viewMat: simd_float4x4
        if let cameraController {
            viewPosition = cameraController.position
            viewMat = cameraController.viewMatrix
        } else {
            animateCamera()
            viewMat = createViewMatrix(
                eyePosition: viewPosition,
                targetPosition: simd_float3(0.0, 2.0, 0.0),
                upVec: simd_float3(0.0, 1.0, 0.0)
            )
        }

        // Deferred step A: write material + normal + depth into the G-Buffer.
        renderingSystem.encodeGeometryPass(
            commandBuffer: commandBuffer,
            drawCalls: drawCalls,
            viewMatrix: viewMat,
            projectionMatrix: projection
        )

        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.03, green: 0.04, blue: 0.055, alpha: 1.0)
        renderPassDescriptor.depthAttachment.clearDepth = 1.0

        // Deferred step B: fullscreen lighting pass reads G-Buffer and outputs lit scene.
        renderingSystem.encodeLightingPass(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            viewPosition: viewPosition,
            directional: dirLight,
            points: pointLights,
            spots: spotLights,
            inverseView: viewMat.inverse,
            inverseProjection: projection.inverse
        )

        // Submit and present frame.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func setCameraController(_ cameraController: CameraFlyController) {
        self.cameraController = cameraController
    }

    func setDebugPreviewMode(index: Int) {
        let mode: RenderingSystem.DebugPreviewMode
        switch index {
        case 2: mode = .albedo
        case 3: mode = .normal
        case 4: mode = .depth
        case 5: mode = .worldPosition
        default: mode = .lit
        }
        renderingSystem.setDebugPreviewMode(mode)
    }

    private func loadScene(device: MTLDevice) {
        // Preferred path: load Sponza so deferred lighting stages are easy to inspect.
        let importer = USDSceneImporter(device: device)
        if let geometry = importer.loadSponzaScene(vertexDescriptor: RenderingSystem.makeGeometryVertexDescriptor()) {
            drawCalls = geometry.drawCalls
            print("[Renderer] Loaded Sponza scene with \(drawCalls.count) draw calls")
            return
        }

        // Fallback path: still exercises the exact same deferred pipeline.
        print("[Renderer] Falling back to built-in cube scene")
        drawCalls = [makeFallbackCubeDrawCall(device: device)]

        dirLight = MtlDirectionalLight(direction: simd_normalize(simd_float3(-0.45, -1.0, -0.2)), color: simd_float3(1.0, 1.0, 1.0), intensity: 1.0)
        pointLights = [
            MtlPointLight(position: simd_float3(2.0, 2.0, 2.0), color: simd_float3(1.0, 0.6, 0.3), intensity: 6.0, radius: 6.0),
            MtlPointLight(position: simd_float3(-2.0, 1.5, -1.0), color: simd_float3(0.3, 0.6, 1.0), intensity: 4.0, radius: 5.0)
        ]
        spotLights = [
            MtlSpotLight(position: simd_float3(0.0, 3.0, 0.0), direction: simd_normalize(simd_float3(0.0, -1.0, 0.0)), color: simd_float3(1.0, 1.0, 0.9), intensity: 8.0, innerCos: cos(10.0 * .pi / 180.0), outerCos: cos(20.0 * .pi / 180.0), radius: 8.0)
        ]
    }

    private func makeFallbackCubeDrawCall(device: MTLDevice) -> GeometryDrawCall {
        // Build one indexed mesh + optional albedo texture.
        let vertexBuffer = device.makeBuffer(
            bytes: cubeVertices,
            length: cubeVertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )!

        let indexBuffer = device.makeBuffer(
            bytes: cubeIndices,
            length: cubeIndices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        )!

        let loader = MTKTextureLoader(device: device)
        let albedoTexture: MTLTexture?
        if let url = Bundle.main.url(forResource: "planks", withExtension: "png") {
            albedoTexture = try? loader.newTexture(URL: url, options: [MTKTextureLoader.Option.SRGB: false])
        } else {
            albedoTexture = nil
        }

        return GeometryDrawCall(
            vertexBuffer: vertexBuffer,
            vertexBufferOffset: 0,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            indexCount: cubeIndices.count,
            indexType: .uint16,
            primitiveType: .triangle,
            modelMatrix: matrix_identity_float4x4,
            albedoTexture: albedoTexture,
            specularStrength: 0.45
        )
    }

    private func animateCamera() {
        // Orbit camera only for the tiny fallback scene (single draw call).
        guard drawCalls.count <= 1 else {
            viewPosition = simd_float3(0.0, 4.0, 15.0)
            return
        }

        let t = Float(Date().timeIntervalSinceReferenceDate)
        viewPosition.x = 5.0 * sin(t)
        viewPosition.z = 5.0 * cos(t)
        viewPosition.y = 3.5
    }
}
