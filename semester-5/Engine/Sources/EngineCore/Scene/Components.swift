import simd

// MARK: - Scene components

public struct Transform: Sendable {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>

    public var matrix: simd_float4x4 {
        Math.translation(position) * simd_float4x4(rotation) * Math.scale(scale)
    }

    public init(
        position: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), scale: SIMD3<Float> = .one
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

public struct WorldTransform: Sendable {
    public var matrix: simd_float4x4

    public init(_ matrix: simd_float4x4) {
        self.matrix = matrix
    }
}

public struct MeshRenderer: Sendable {
    public var mesh: MeshID
    public var material: MaterialID

    public init(mesh: MeshID, material: MaterialID) {
        self.mesh = mesh
        self.material = material
    }
}

public struct Camera: Sendable {
    public var near: Float = 0.1
    public var far: Float = 100
    public var yaw: Float = 0
    public var pitch: Float = 0

    public init() {}
}

public struct DirectionalLight: Sendable {
    public var direction: SIMD3<Float>
    public var color: SIMD3<Float>
    public var intensity: Float

    public init(
        direction: SIMD3<Float> = SIMD3(-0.5, -1, -0.6), color: SIMD3<Float> = .one,
        intensity: Float = 2
    ) {
        self.direction = direction
        self.color = color
        self.intensity = intensity
    }
}

public struct Spin: Sendable {
    public var speed: Float

    public init(speed: Float = 0.5) {
        self.speed = speed
    }
}
