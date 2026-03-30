import Metal
import simd

final class DeferredScene: RenderScene {
    let ambientLight: MtlAmbientLight
    let directionalLight: MtlDirectionalLight
    let pointLights: [MtlPointLight]
    let spotLights: [MtlSpotLight]
    let geometryRendererKind: GeometryRendererKind = .deferredIndexed
    let prefersOrbitingCamera: Bool
    let preferredCameraPosition: simd_float3
    let preferredCameraYaw: Float
    let preferredCameraPitch: Float

    private let drawCalls: [GeometryDrawCall]

    init(device: MTLDevice, geometryVertexDescriptor: MTLVertexDescriptor) {
        let importer = USDSceneImporter(device: device)
        if let geometry = importer.loadSponzaScene(vertexDescriptor: geometryVertexDescriptor) {
            self.drawCalls = geometry.drawCalls
            self.prefersOrbitingCamera = false
            self.preferredCameraPosition = simd_float3(0.0, 4.0, 15.0)
            self.preferredCameraYaw = -.pi / 2.0
            self.preferredCameraPitch = 0.0
            self.ambientLight = MtlAmbientLight(color: simd_float3(1.0, 0.98, 0.95), intensity: 0.01)
            self.directionalLight = MtlDirectionalLight(
                direction: simd_normalize(simd_float3(-0.25, -1.0, -0.15)),
                color: simd_float3(1.0, 0.98, 0.95),
                intensity: 0.02
            )
            self.pointLights = [
                MtlPointLight(position: simd_float3(-500.0, 300.0, 0.0), color: simd_float3(1.0, 0.55, 0.32), intensity: 2.0, radius: 700.0),
                MtlPointLight(position: simd_float3(0.0, 300.0, -400.0), color: simd_float3(0.35, 0.55, 1.0), intensity: 2.0, radius: 800.0),
                MtlPointLight(position: simd_float3(500.0, 300.0, 150.0), color: simd_float3(1.0, 0.8, 0.45), intensity: 2.0, radius: 700.0),
                MtlPointLight(position: simd_float3(0.0, 500.0, 600.0), color: simd_float3(0.5, 1.0, 0.8), intensity: 2.0, radius: 900.0)
            ]
            self.spotLights = [
                MtlSpotLight(position: simd_float3(-0.0, 300.0, 0.0), direction: simd_normalize(simd_float3(1.0, 0.0, 0.0)), color: simd_float3(1.0, 0.0, 0.0), intensity: 28.0, innerCos: cos(12.0 * .pi / 180.0), outerCos: cos(22.0 * .pi / 180.0), radius: 1800.0)
            ]
            print("[Renderer] Loaded Deferred scene: Sponza (\(geometry.drawCalls.count) draw calls)")
            return
        }

        self.drawCalls = [GeometryPrimitives.makeCubeDrawCall(device: device)]
        self.prefersOrbitingCamera = true
        self.preferredCameraPosition = simd_float3(0.0, 4.0, 15.0)
        self.preferredCameraYaw = -.pi / 2.0
        self.preferredCameraPitch = 0.0
        self.ambientLight = MtlAmbientLight(color: simd_float3(repeating: 1.0), intensity: 0.10)
        self.directionalLight = MtlDirectionalLight(
            direction: simd_normalize(simd_float3(-0.45, -1.0, -0.2)),
            color: simd_float3(1.0, 1.0, 1.0),
            intensity: 0.22
        )
        self.pointLights = []
        self.spotLights = []
        print("[Renderer] Loaded Deferred fallback scene: Cube")
    }

    func makeDrawCalls(cameraPosition: simd_float3) -> [GeometryDrawCall] {
        drawCalls
    }
}
