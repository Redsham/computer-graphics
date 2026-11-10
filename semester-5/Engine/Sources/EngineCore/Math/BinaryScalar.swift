// MARK: - Binary decoding

/// IEEE 754 half decoding without Float16, which is unavailable in Intel package slices.
public enum BinaryScalar {
    public static func float16(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = Int((bits >> 10) & 31)
        var mantissa = UInt32(bits & 1023)

        if exponent == 31 {
            return Float(bitPattern: sign | 0x7f80_0000 | (mantissa << 13))
        }

        if exponent == 0 {
            if mantissa == 0 {
                return Float(bitPattern: sign)
            }

            var unbiased = -14

            while mantissa & 1024 == 0 {
                mantissa <<= 1
                unbiased -= 1
            }

            return Float(bitPattern: sign | (UInt32(unbiased + 127) << 23) | ((mantissa & 1023) << 13))
        }

        return Float(bitPattern: sign | (UInt32(exponent + 112) << 23) | (mantissa << 13))
    }
}
