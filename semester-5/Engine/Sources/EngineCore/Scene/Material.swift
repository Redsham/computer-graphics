import simd

// MARK: - Materials

public struct Material: Sendable {
    public var baseColor: SIMD3<Float>

    public init(baseColor: SIMD3<Float>) {
        self.baseColor = baseColor
    }
}
