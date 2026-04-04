import Metal
import simd

final class TessellationScene: RenderScene {
    struct Settings {
        var patchSize: simd_float2 = simd_float2(repeating: 420.0)
        var patchCenter: simd_float2 = simd_float2(0.0, -220.0)
        var patchResolution: Int = 8
        var minTessellationFactor: Float = 1.0
        var maxTessellationFactor: Float = 32.0
        var minDistance: Float = 200.0
        var maxDistance: Float = 1800.0
        var displacementScale: Float = 9.0
        var uvScale: simd_float2 = simd_float2(repeating: 1.35)
        var normalStrength: Float = 0.55
        var waveAmplitude: Float = 2.6
        var waveFrequency: Float = 13.0
        var waveSpeed: Float = 1.3
        var specularStrength: Float = 0.22
        var roughness: Float = 0.88
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
            center: settings.patchCenter,
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
            tessellationBoundsMin: terrain.boundsMin,
            tessellationBoundsMax: terrain.boundsMax,
            minTessellationFactor: settings.minTessellationFactor,
            maxTessellationFactor: settings.maxTessellationFactor,
            minTessellationDistance: settings.minDistance,
            maxTessellationDistance: settings.maxDistance,
            modelMatrix: matrix_identity_float4x4,
            displacementScale: settings.displacementScale,
            uvScale: simd_max(settings.uvScale * (settings.patchSize / 420.0), simd_float2(repeating: 0.001)),
            normalStrength: settings.normalStrength,
            waveAmplitude: settings.waveAmplitude,
            waveFrequency: settings.waveFrequency,
            waveSpeed: settings.waveSpeed,
            material: MaterialDrawState(
                albedoTexture: textures.albedo,
                normalTexture: textures.normal,
                displacementTexture: textures.displacement,
                specularStrength: settings.specularStrength,
                roughness: settings.roughness,
                opacity: 0.38
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
