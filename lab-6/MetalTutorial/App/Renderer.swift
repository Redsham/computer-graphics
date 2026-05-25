import Metal
import MetalKit
import QuartzCore
import simd

struct RendererCullingHUDState {
    var frustumEnabled: Bool
    var octreeEnabled: Bool
    var splitDebugEnabled: Bool
    var stats: CullingStats
    var sceneStatus: String?
}

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
    var onCullingStateUpdate: ((RendererCullingHUDState) -> Void)?
    var onThrustUpdate: ((Float) -> Void)?

    // Camera state used to build view/projection matrices every frame.
    private var viewPosition = simd_float3(0.0, 4.0, 15.0)
    private var aspectRatio: Float = 1.0
    private var cameraController: CameraFlyController?
    private var lastFPSUpdateTime = CACurrentMediaTime()
    private var accumulatedFrameTime: Double = 0.0
    private var accumulatedFrameCount: Int = 0
    private var frustumCullingEnabled = false
    private var octreeCullingEnabled = false
    private var splitScreenDebugEnabled = false
    private var rocketThrust: Float = 0.72

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
        loadScene(device: device, view: metalKitView)
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

        let mainViewport = splitScreenDebugEnabled ? makeMainSplitViewport(size: view.drawableSize) : nil
        let mainAspectRatio: Float
        if splitScreenDebugEnabled {
            mainAspectRatio = Float((view.drawableSize.width * 0.5) / max(view.drawableSize.height, 1.0))
        } else {
            mainAspectRatio = aspectRatio
        }
        let farPlane = min(max(simd_length(scene.sceneBounds.extent) * 3.0, 1500.0), 50000.0)
        let projection = createPerspectiveMatrix(
            fov: toRadians(from: 50.0),
            aspectRatio: mainAspectRatio,
            nearPlane: 0.05,
            farPlane: farPlane
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

        let cullingOptions = CullingOptions(
            frustumCullingEnabled: frustumCullingEnabled,
            octreeCullingEnabled: octreeCullingEnabled,
            collectDebugInfo: splitScreenDebugEnabled
        )
        let frameData = scene.makeFrameData(
            viewMatrix: viewMat,
            projectionMatrix: projection,
            cullingOptions: cullingOptions
        )
        notifyCullingState(stats: frameData.stats)

        // Deferred step A: write material + normal + depth into the G-Buffer.
        renderingSystem.encodeGeometryPass(
            commandBuffer: commandBuffer,
            drawCalls: frameData.drawCalls,
            rendererKind: scene.geometryRendererKind,
            cameraPosition: viewPosition,
            time: time,
            viewMatrix: viewMat,
            projectionMatrix: projection,
            renderViewport: mainViewport
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
            inverseProjection: projection.inverse,
            renderViewport: mainViewport
        )

        renderingSystem.encodeTransparentPass(
            commandBuffer: commandBuffer,
            drawableTexture: drawable.texture,
            drawCalls: frameData.drawCalls,
            viewPosition: viewPosition,
            ambient: ambientLight,
            directional: dirLight,
            points: pointLights + impulseLightSystem.makePointLights(),
            spots: spotLights,
            debugPreviewMode: renderingSystem.debugPreviewModeValue,
            time: time,
            viewMatrix: viewMat,
            projectionMatrix: projection,
            renderViewport: mainViewport
        )

        scene.encodeParticles(
            commandBuffer: commandBuffer,
            drawableTexture: drawable.texture,
            depthTexture: renderingSystem.sceneDepthTexture,
            viewMatrix: viewMat,
            projectionMatrix: projection,
            time: time,
            deltaTime: deltaTime,
            throttle: rocketThrust,
            renderViewport: mainViewport
        )

        if splitScreenDebugEnabled {
            let debugViewport = makeDebugSplitViewport(size: view.drawableSize)
            let debugCamera = makeDebugCamera(sceneBounds: frameData.sceneBounds, aspectRatio: mainAspectRatio)
            let debugLines = makeCullingDebugLines(
                frameData: frameData,
                mainViewMatrix: viewMat,
                mainProjectionMatrix: projection
            )
            renderingSystem.encodeDebugLinePass(
                commandBuffer: commandBuffer,
                drawableTexture: drawable.texture,
                lines: debugLines,
                viewMatrix: debugCamera.view,
                projectionMatrix: debugCamera.projection,
                renderViewport: debugViewport
            )
        }

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

    func toggleFrustumCulling() {
        frustumCullingEnabled.toggle()
        print("[Renderer] Frustum culling -> \(frustumCullingEnabled ? "On" : "Off")")
    }

    func toggleOctreeCulling() {
        octreeCullingEnabled.toggle()
        print("[Renderer] Octree culling -> \(octreeCullingEnabled ? "On" : "Off")")
    }

    func toggleSplitScreenDebug() {
        splitScreenDebugEnabled.toggle()
        print("[Renderer] Split-screen culling debug -> \(splitScreenDebugEnabled ? "On" : "Off")")
    }

    func setRocketThrust(_ value: Float) {
        rocketThrust = max(0.0, min(1.0, value))
        onThrustUpdate?(rocketThrust)
    }

    func adjustRocketThrust(by delta: Float) {
        setRocketThrust(rocketThrust + delta)
    }

    private func loadScene(device: MTLDevice, view: MTKView) {
        applyScene(DeferredScene(device: device, view: view, geometryVertexDescriptor: renderingSystem.geometryVertexDescriptorValue))
    }

    private func applyScene(_ nextScene: any RenderScene) {
        scene = nextScene
        ambientLight = scene.ambientLight
        dirLight = scene.directionalLight
        pointLights = scene.pointLights
        spotLights = scene.spotLights
        renderingSystem.setDebugPreviewMode(.lit)
        onDebugModeUpdate?(debugModeTitle(for: .lit))
        notifyCullingState(stats: CullingStats(totalObjects: 0, visibleObjects: 0, culledObjects: 0, visitedOctreeNodes: 0))
        onThrustUpdate?(rocketThrust)
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

    private func notifyCullingState(stats: CullingStats) {
        let statusLines = [scene.hudStatus, scene.particleStatus]
            .compactMap { $0 }
            .joined(separator: "\n")
        onCullingStateUpdate?(
            RendererCullingHUDState(
                frustumEnabled: frustumCullingEnabled || octreeCullingEnabled,
                octreeEnabled: octreeCullingEnabled,
                splitDebugEnabled: splitScreenDebugEnabled,
                stats: stats,
                sceneStatus: statusLines.isEmpty ? nil : statusLines
            )
        )
    }

    private func makeMainSplitViewport(size: CGSize) -> RenderViewport {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        let halfWidth = max(width / 2, 1)
        return RenderViewport(
            viewport: MTLViewport(originX: 0.0, originY: 0.0, width: Double(halfWidth), height: Double(height), znear: 0.0, zfar: 1.0),
            scissorRect: MTLScissorRect(x: 0, y: 0, width: halfWidth, height: height),
            gBufferUVTransform: simd_float4(0.5, 1.0, 0.0, 0.0)
        )
    }

    private func makeDebugSplitViewport(size: CGSize) -> RenderViewport {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        let halfWidth = max(width / 2, 1)
        let rightWidth = max(width - halfWidth, 1)
        return RenderViewport(
            viewport: MTLViewport(originX: Double(halfWidth), originY: 0.0, width: Double(rightWidth), height: Double(height), znear: 0.0, zfar: 1.0),
            scissorRect: MTLScissorRect(x: halfWidth, y: 0, width: rightWidth, height: height),
            gBufferUVTransform: simd_float4(0.5, 1.0, 0.5, 0.0)
        )
    }

    private func makeDebugCamera(sceneBounds: AABB, aspectRatio: Float) -> (view: simd_float4x4, projection: simd_float4x4) {
        let center = sceneBounds.center
        let extent = sceneBounds.extent
        let radius = max(max(extent.x, extent.y), extent.z)
        let eye = center + simd_float3(radius * 0.72, max(radius * 0.5, 900.0), radius * 1.12)
        let view = createViewMatrix(
            eyePosition: eye,
            targetPosition: center,
            upVec: simd_float3(0.0, 1.0, 0.0)
        )
        let projection = createPerspectiveMatrix(
            fov: toRadians(from: 54.0),
            aspectRatio: aspectRatio,
            nearPlane: 1.0,
            farPlane: max(radius * 4.0, 5000.0)
        )
        return (view, projection)
    }

    private func makeCullingDebugLines(frameData: SceneFrameData,
                                       mainViewMatrix: simd_float4x4,
                                       mainProjectionMatrix: simd_float4x4) -> [DebugLineVertex] {
        var lines: [DebugLineVertex] = []
        lines.reserveCapacity(frameData.debugObjects.count * 24 + 256)

        let visibleColor = simd_float4(0.12, 1.0, 0.36, 0.72)
        let culledColor = simd_float4(1.0, 0.12, 0.08, 0.32)
        let octreeColor = simd_float4(0.2, 0.62, 1.0, 0.18)
        let frustumColor = simd_float4(1.0, 0.88, 0.08, 1.0)

        for bounds in frameData.octreeDebugBounds.prefix(512) {
            appendBoxLines(bounds: bounds, color: octreeColor, lines: &lines)
        }

        for object in frameData.debugObjects {
            appendBoxLines(bounds: object.bounds, color: object.isVisible ? visibleColor : culledColor, lines: &lines)
        }

        let frustumCorners = ViewFrustum.worldCorners(
            viewMatrix: mainViewMatrix,
            projectionMatrix: mainProjectionMatrix
        )
        appendFrustumLines(corners: frustumCorners, color: frustumColor, lines: &lines)
        return lines
    }

    private func appendBoxLines(bounds: AABB, color: simd_float4, lines: inout [DebugLineVertex]) {
        guard bounds.isValid else { return }
        let c = bounds.corners
        let edges = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        for edge in edges {
            appendLine(from: c[edge.0], to: c[edge.1], color: color, lines: &lines)
        }
    }

    private func appendFrustumLines(corners: [simd_float3], color: simd_float4, lines: inout [DebugLineVertex]) {
        guard corners.count == 8 else { return }
        let edges = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        for edge in edges {
            appendLine(from: corners[edge.0], to: corners[edge.1], color: color, lines: &lines)
        }
    }

    private func appendLine(from start: simd_float3,
                            to end: simd_float3,
                            color: simd_float4,
                            lines: inout [DebugLineVertex]) {
        lines.append(DebugLineVertex(position: start, color: color))
        lines.append(DebugLineVertex(position: end, color: color))
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
