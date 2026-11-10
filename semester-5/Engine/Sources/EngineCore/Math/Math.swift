import simd

public enum Math {
    public static func translation(_ p: SIMD3<Float>) -> simd_float4x4 {
        var result = matrix_identity_float4x4
        result.columns.3 = SIMD4(p, 1)
        return result
    }

    public static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s, 1))
    }

    /// Right handed world; camera looks down -Z, Metal depth is 0...1.
    public static func perspective(fovDegrees: Float, aspect: Float, near: Float, far: Float)
        -> simd_float4x4
    {
        let y = 1 / tan(fovDegrees * .pi / 360)
        let z = far / (near - far)
        return simd_float4x4(
            columns: (
                SIMD4(y / max(aspect, 0.0001), 0, 0, 0), SIMD4(0, y, 0, 0),
                SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)
            ))
    }
}

public struct FrameClock {
    private var previous: Double?

    public init() {}

    public mutating func tick(at time: Double) -> Float {
        defer {
            previous = time
        }

        guard let previous else {
            return 0
        }

        return Float(min(max(time - previous, 0), 0.1))
    }

    public mutating func reset() {
        previous = nil
    }
}
