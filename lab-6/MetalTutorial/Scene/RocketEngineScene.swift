import Metal
import simd

final class RocketEngineScene: RenderScene {
    let ambientLight: MtlAmbientLight
    let directionalLight: MtlDirectionalLight
    let pointLights: [MtlPointLight]
    let spotLights: [MtlSpotLight]
    let geometryRendererKind: GeometryRendererKind = .deferredIndexed
    let prefersOrbitingCamera: Bool = false
    let preferredCameraPosition: simd_float3 = simd_float3(0.0, 10.0, 430.0)
    let preferredCameraYaw: Float = -.pi / 2.0
    let preferredCameraPitch: Float = -0.04
    let sceneBounds: AABB

    private let objects: [CullingObject]
    private let octree: Octree

    var hudStatus: String? {
        """
        Scene : Rocket engine
        Input : slider / +/- thrust
        GPU   : compute particles
        """
    }

    init(device: MTLDevice) {
        let nozzle = GeometryPrimitives.makeConeDrawCall(
            device: device,
            radius: 34.0,
            height: 76.0,
            color: simd_float4(0.10, 0.11, 0.13, 1.0)
        )

        var drawCalls: [GeometryDrawCall] = []
        drawCalls.append(Self.transformed(nozzle) { model in
            translateMatrix(matrix: &model, position: simd_float3(0.0, -16.0, 0.0))
            rotateMatrix(matrix: &model, rotation: simd_float3(.pi, 0.0, 0.0))
        })

        let bounds = AABB(
            min: simd_float3(-220.0, -360.0, -220.0),
            max: simd_float3(220.0, 80.0, 220.0)
        )
        let object = CullingObject(
            id: 0,
            bounds: bounds,
            drawCalls: drawCalls,
            label: "Rocket nozzle"
        )
        self.objects = [object]
        self.sceneBounds = bounds
        self.octree = Octree(objects: [object])
        self.ambientLight = MtlAmbientLight(color: simd_float3(0.82, 0.86, 0.92), intensity: 0.08)
        self.directionalLight = MtlDirectionalLight(
            direction: simd_normalize(simd_float3(-0.42, -1.0, -0.35)),
            color: simd_float3(0.95, 0.98, 1.0),
            intensity: 0.36
        )
        self.pointLights = [
            MtlPointLight(position: simd_float3(-180.0, 180.0, 260.0), color: simd_float3(0.35, 0.55, 1.0), intensity: 2.0, radius: 760.0),
            MtlPointLight(position: simd_float3(110.0, -75.0, 90.0), color: simd_float3(1.0, 0.45, 0.16), intensity: 3.0, radius: 420.0)
        ]
        self.spotLights = [
            MtlSpotLight(
                position: simd_float3(0.0, -35.0, 0.0),
                direction: simd_float3(0.0, -1.0, 0.0),
                color: simd_float3(1.0, 0.45, 0.12),
                intensity: 18.0,
                innerCos: cos(18.0 * .pi / 180.0),
                outerCos: cos(34.0 * .pi / 180.0),
                radius: 520.0
            )
        ]
    }

    func makeFrameData(viewMatrix: simd_float4x4,
                       projectionMatrix: simd_float4x4,
                       cullingOptions: CullingOptions) -> SceneFrameData {
        SceneCullingEvaluator.makeFrameData(
            objects: objects,
            octree: octree,
            sceneBounds: sceneBounds,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            options: cullingOptions
        )
    }

    private static func transformed(_ drawCall: GeometryDrawCall,
                                    update: (inout simd_float4x4) -> Void) -> GeometryDrawCall {
        guard case var .indexed(indexedDrawCall) = drawCall else { return drawCall }
        var model = matrix_identity_float4x4
        update(&model)
        indexedDrawCall.modelMatrix = model
        return .indexed(indexedDrawCall)
    }
}
