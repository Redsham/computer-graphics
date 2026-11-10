import simd

// MARK: - Render data

public struct RenderObject: Sendable {
    public let mesh: MeshID
    public let material: MaterialID
    public let model: simd_float4x4

    public init(mesh: MeshID, material: MaterialID, model: simd_float4x4) {
        self.mesh = mesh
        self.material = material
        self.model = model
    }
}

public struct RenderSnapshot: Sendable {
    public var viewProjection = matrix_identity_float4x4
    public var light = DirectionalLight()
    public var objects: [RenderObject] = []

    public init() {}
}
