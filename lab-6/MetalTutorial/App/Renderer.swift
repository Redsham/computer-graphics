import Metal
import MetalKit
import QuartzCore
import simd

// Top-level frame orchestrator:
// 1) updates camera and matrices,
// 2) records geometry pass into the G-Buffer,
// 3) records lighting pass that resolves final color to the swapchain.
final class Renderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let renderingSystem: RenderingSystem

    private var scene: (any RenderScene)!
    var onFPSUpdate: ((Double) -> Void)?
    var onDebugModeUpdate: ((String) -> Void)?

    // Camera state used to build view/projection matrices every frame.
    private var viewPosition = simd_float3(0.0, 4.0, 15.0)
    private var aspectRatio: Float = 1.0
    private var cameraController: CameraFlyController?
    private var lastFPSUpdateTime = CACurrentMediaTime()
    private var accumulatedFrameTime: Double = 0.0
    private var accumulatedFrameCount: Int = 0

    // Scene light sets consumed during deferred lighting.
    private var ambientLight: MtlAmbientLight
    private var dirLight: MtlDirectionalLight
    private var pointLights: [MtlPointLight]
    private var spotLights: [MtlSpotLight]
    private let impulseLightSystem = ImpulsePointLightSystem()

    init?(metalKitView: MTKView) {
        // Bootstrap Metal device/queue and configure drawable formats.
        guard let device = metalKitView.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        metalKitView.colorPixelFormat = .bgra8Unorm_srgb
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.sampleCount = 1

        self.renderingSystem = RenderingSystem(device: device, view: metalKitView)

        self.ambientLight = MtlAmbientLight(color: simd_float3(repeating: 1.0), intensity: 0.03)
        self.dirLight = MtlDirectionalLight(direction: simd_float3(0, -1, 0), color: simd_float3(1, 1, 1), intensity: 0.0)
        self.pointLights = []
        self.spotLights = []

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

        updateFPS()

        // Update camera movement and derive matrices.
        let deltaTime = max(Float(view.preferredFramesPerSecond > 0 ? 1.0 / Double(view.preferredFramesPerSecond) : 1.0 / 60.0), 1.0 / 240.0)
        let time = Float(CACurrentMediaTime())
        cameraController?.update(deltaTime: deltaTime)
        impulseLightSystem.update(deltaTime: deltaTime)

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
            drawCalls: scene.makeDrawCalls(cameraPosition: viewPosition),
            rendererKind: scene.geometryRendererKind,
            cameraPosition: viewPosition,
            time: time,
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
            ambient: ambientLight,
            directional: dirLight,
            points: pointLights + impulseLightSystem.makePointLights(),
            spots: spotLights,
            inverseView: viewMat.inverse,
            inverseProjection: projection.inverse
        )

        renderingSystem.encodeTransparentPass(
            commandBuffer: commandBuffer,
            drawableTexture: drawable.texture,
            drawCalls: scene.makeDrawCalls(cameraPosition: viewPosition),
            viewPosition: viewPosition,
            ambient: ambientLight,
            directional: dirLight,
            points: pointLights + impulseLightSystem.makePointLights(),
            spots: spotLights,
            debugPreviewMode: renderingSystem.debugPreviewModeValue,
            time: time,
            viewMatrix: viewMat,
            projectionMatrix: projection
        )

        // Submit and present frame.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func setCameraController(_ cameraController: CameraFlyController) {
        self.cameraController = cameraController
        cameraController.setPose(
            position: scene.preferredCameraPosition,
            yaw: scene.preferredCameraYaw,
            pitch: scene.preferredCameraPitch
        )
        viewPosition = scene.preferredCameraPosition
    }

    func spawnImpulseLightFromCamera() {
        guard let cameraController else { return }
        let spawnOffset: Float = 1.0
        let spawnPosition = cameraController.position + cameraController.forwardVector * spawnOffset
        impulseLightSystem.spawn(at: spawnPosition, forward: cameraController.forwardVector)
    }

    func setDebugPreviewMode(index: Int) {
        let mode: RenderingSystem.DebugPreviewMode
        switch index {
        case 2: mode = .albedo
        case 3: mode = .normal
        case 4: mode = .depth
        case 5: mode = .worldPosition
        case 6: mode = .wireframe
        default: mode = .lit
        }
        renderingSystem.setDebugPreviewMode(mode)
        onDebugModeUpdate?(debugModeTitle(for: mode))
    }

    private func loadScene(device: MTLDevice) {
        applyScene(DeferredScene(
            device: device,
            geometryVertexDescriptor: RenderingSystem.makeGeometryVertexDescriptor()
        ))
    }

    private func applyScene(_ nextScene: any RenderScene) {
        scene = nextScene
        ambientLight = scene.ambientLight
        dirLight = scene.directionalLight
        pointLights = scene.pointLights
        spotLights = scene.spotLights
        renderingSystem.setDebugPreviewMode(.lit)
        onDebugModeUpdate?(debugModeTitle(for: .lit))
        viewPosition = scene.preferredCameraPosition
        cameraController?.setPose(
            position: scene.preferredCameraPosition,
            yaw: scene.preferredCameraYaw,
            pitch: scene.preferredCameraPitch
        )
    }

    private func animateCamera() {
        // Orbit camera only for simple scenes like the cube fallback.
        guard scene.prefersOrbitingCamera else {
            viewPosition = simd_float3(0.0, 4.0, 15.0)
            return
        }

        let t = Float(Date().timeIntervalSinceReferenceDate)
        viewPosition.x = 5.0 * sin(t)
        viewPosition.z = 5.0 * cos(t)
        viewPosition.y = 3.5
    }

    private func updateFPS() {
        let now = CACurrentMediaTime()
        let frameTime = now - lastFPSUpdateTime
        lastFPSUpdateTime = now

        guard frameTime > 0 else { return }

        accumulatedFrameTime += frameTime
        accumulatedFrameCount += 1

        guard accumulatedFrameTime >= 0.25 else { return }

        let fps = Double(accumulatedFrameCount) / accumulatedFrameTime
        accumulatedFrameTime = 0.0
        accumulatedFrameCount = 0
        onFPSUpdate?(fps)
    }

    private func debugModeTitle(for mode: RenderingSystem.DebugPreviewMode) -> String {
        switch mode {
        case .lit:
            return "Lit"
        case .albedo:
            return "Albedo"
        case .normal:
            return "Normal"
        case .depth:
            return "Depth"
        case .worldPosition:
            return "World Position"
        case .wireframe:
            return "Wireframe"
        }
    }
}
