import simd

final class ImpulsePointLightSystem {
    private struct ImpulseLight {
        var position: simd_float3
        var velocity: simd_float3
        var color: simd_float3
        var baseIntensity: Float
        var radius: Float
        var age: Float = 0.0
        var lifetime: Float
    }

    private var impulseLights: [ImpulseLight] = []

    func spawn(at position: simd_float3,
               forward: simd_float3,
               speed: Float = 4200.0,
               color: simd_float3 = randomColorHSV(),
               intensity: Float = 16.0,
               radius: Float = 900.0,
               lifetime: Float = 2.5) {
        let normalizedForward = simd_normalize(forward)
        let light = ImpulseLight(
            position: position,
            velocity: normalizedForward * speed,
            color: color,
            baseIntensity: intensity,
            radius: radius,
            lifetime: lifetime
        )
        impulseLights.append(light)
    }

    func update(deltaTime: Float) {
        guard !impulseLights.isEmpty else { return }

        for index in impulseLights.indices {
            impulseLights[index].position += impulseLights[index].velocity * deltaTime
            impulseLights[index].age += deltaTime
        }

        impulseLights.removeAll { $0.age >= $0.lifetime }
    }

    func makePointLights() -> [MtlPointLight] {
        impulseLights.map { light in
            let fade = max(0.0, 1.0 - (light.age / max(light.lifetime, 0.001)))
            return MtlPointLight(
                position: light.position,
                color: light.color,
                intensity: light.baseIntensity * fade,
                radius: light.radius
            )
        }
    }
    
    private static func randomColorHSV() -> simd_float3 {
        let h = Float.random(in: 0...1)
        let s: Float = 0.8
        let v: Float = 1.0
        return hsvToRgb(h: h, s: s, v: v)
    }
    
    private static func hsvToRgb(h: Float, s: Float, v: Float) -> simd_float3 {
        let i = floor(h * 6.0)
        let f = h * 6.0 - i
        let p = v * (1.0 - s)
        let q = v * (1.0 - f * s)
        let t = v * (1.0 - (1.0 - f) * s)

        switch Int(i) % 6 {
        case 0: return simd_float3(v, t, p)
        case 1: return simd_float3(q, v, p)
        case 2: return simd_float3(p, v, t)
        case 3: return simd_float3(p, q, v)
        case 4: return simd_float3(t, p, v)
        case 5: return simd_float3(v, p, q)
        default: return simd_float3(1, 1, 1)
        }
    }
}
