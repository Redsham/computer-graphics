import simd

// MARK: - Resource identifiers

public struct MeshID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ value: UInt64) {
        rawValue = value
    }
}

public struct MaterialID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ value: UInt64) {
        rawValue = value
    }
}

// MARK: - Materials

public struct Material: Sendable {
    public var baseColor: SIMD3<Float>

    public init(baseColor: SIMD3<Float>) {
        self.baseColor = baseColor
    }
}

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

// MARK: - Input data

public struct InputSnapshot: Sendable {
    public var movement: SIMD3<Float> = .zero
    public var look: SIMD2<Float> = .zero

    public init(movement: SIMD3<Float> = .zero, look: SIMD2<Float> = .zero) {
        self.movement = movement
        self.look = look
    }
}
