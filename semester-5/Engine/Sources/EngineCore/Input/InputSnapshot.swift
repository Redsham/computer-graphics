import simd

// MARK: - Input data

public struct InputSnapshot: Sendable {
    public var movement: SIMD3<Float> = .zero
    public var look: SIMD2<Float> = .zero

    public init(movement: SIMD3<Float> = .zero, look: SIMD2<Float> = .zero) {
        self.movement = movement
        self.look = look
    }
}
