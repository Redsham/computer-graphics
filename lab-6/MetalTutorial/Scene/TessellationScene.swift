import Metal
import simd

final class TessellationScene: RenderScene {
    struct Settings {
        var patchSize: Float = 420.0
        var patchCenterZ: Float = -220.0
        var patchResolution: Int = 16
        var minTessellationFactor: Float = 1.0
        var maxTessellationFactor: Float = 32.0
        var minDistance: Float = 200.0
        var maxDistance: Float = 1800.0
        var displacementScale: Float = 16.0
        var uvScale: simd_float2 = simd_float2(repeating: 1.0)
        var normalStrength: Float = 1.0
    }

    let ambientLight: MtlAmbientLight
    let directionalLight: MtlDirectionalLight
    let pointLights: [MtlPointLight]
    let spotLights: [MtlSpotLight]
    let geometryRendererKind: GeometryRendererKind = .tessellatedTerrain
    let prefersOrbitingCamera: Bool
    let preferredCameraPosition: simd_float3
    let preferredCameraYaw: Float
    let preferredCameraPitch: Float
    let settings: Settings

    private let drawCall: GeometryDrawCall

    init(device: MTLDevice, settings: Settings = Settings()) {
        self.settings = settings
        let textures = TextureSetLoader(device: device).loadTextureSet(
            albedo: (name: "cliff_side_diff_2k", ext: "jpg"),
            normal: (name: "cliff_side_nor_2k", ext: "jpg"),
            displacement: (name: "cliff_side_disp_2k", ext: "png")
        )
        let terrain = GeometryPrimitives.makeTerrainPatch(
            device: device,
            size: settings.patchSize,
            centerZ: settings.patchCenterZ,
            patchResolution: settings.patchResolution,
            minFactor: settings.minTessellationFactor,
            maxFactor: settings.maxTessellationFactor,
            minDistance: settings.minDistance,
            maxDistance: settings.maxDistance
        )
        self.drawCall = .tessellated(TessellatedGeometryDrawCall(
            controlPointBuffer: terrain.controlPointBuffer,
            patchInfoBuffer: terrain.patchInfoBuffer,
            tessellationFactorBuffer: terrain.tessellationFactorBuffer,
            patchCount: terrain.patchCount,
            modelMatrix: matrix_identity_float4x4,
            displacementScale: settings.displacementScale,
            uvScale: settings.uvScale,
            normalStrength: settings.normalStrength,
            material: MaterialDrawState(
                albedoTexture: textures.albedo,
                normalTexture: textures.normal,
                displacementTexture: textures.displacement,
                specularStrength: 0.0
            )
        ))
        self.ambientLight = MtlAmbientLight(color: simd_float3(1.0, 0.98, 0.95), intensity: 0.5)
        self.directionalLight = MtlDirectionalLight(
            direction: simd_normalize(simd_float3(-0.35, -1.0, -0.1)),
            color: simd_float3(1.0, 1.0, 1.0),
            intensity: 1.0
        )
        self.pointLights = []
        self.spotLights = []
        self.prefersOrbitingCamera = false
        self.preferredCameraPosition = simd_float3(0.0, 70.0, 120.0)
        self.preferredCameraYaw = -.pi / 2.0
        self.preferredCameraPitch = -0.35
    }

    func makeDrawCalls(cameraPosition: simd_float3) -> [GeometryDrawCall] {
        _ = cameraPosition
        return [drawCall]
    }
}
