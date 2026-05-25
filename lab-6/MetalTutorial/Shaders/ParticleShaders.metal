#include <metal_stdlib>
using namespace metal;

struct Particle {
    float4 positionSeed;
    float4 velocityDrag;
    float4 color;
    float4 ageLifeSizeRandom;
};

struct ParticleUniforms {
    float4 emitterPosition;
    float4 emitterDirection;
    float4 emitterRight;
    float4 emitterUp;
    float4 cameraRight;
    float4 cameraUp;
    float4 timing;
    float4 shape;
    float4 velocity;
    float4 lifeSize;
    float4 behavior;
    float4 colorStart;
    float4 colorMid;
    float4 colorEnd;
    float4 fade;
};

struct ParticleSortKey {
    float depth;
    uint particleIndex;
};

struct ParticleCollisionUniforms {
    float4x4 viewProjection;
    float4x4 inverseViewProjection;
    float4 uvTransform;
    float4 params;
    float4 planeCenter;
    float4 planeNormal;
    float4 planeTangent;
    float4 planeBitangent;
    float4 planeParams;
};

struct SortParams {
    uint stage;
    uint pass;
    uint count;
    uint padding;
};

static inline ParticleSortKey makeSortKey(float depth, uint particleIndex) {
    ParticleSortKey key;
    key.depth = depth;
    key.particleIndex = particleIndex;
    return key;
}

static inline float hash11(float n) {
    return fract(sin(n) * 43758.5453123);
}

static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static inline float2 randomDisk(float seed) {
    float angle = hash11(seed + 2.17) * 6.28318530718;
    float radius = sqrt(hash11(seed + 8.83));
    return float2(cos(angle), sin(angle)) * radius;
}

static inline Particle makeParticle(uint id, constant ParticleUniforms &uniforms, float respawnTime, bool staggerAge) {
    float throttle = saturate(uniforms.timing.z);
    float3 exhaustDir = normalize(uniforms.emitterDirection.xyz);
    float3 emitterRight = normalize(uniforms.emitterRight.xyz);
    float3 emitterUp = normalize(uniforms.emitterUp.xyz);
    float seed = hash21(float2((float)id + 1.0, floor(respawnTime * 113.0) + 19.0));
    float2 disk = randomDisk(seed + hash11((float)id * 0.37));
    float radius = mix(uniforms.shape.x, uniforms.shape.y, sqrt(hash11(seed + 1.7))) * (0.72 + throttle * 0.28);
    float3 radialDirection = emitterRight * disk.x + emitterUp * disk.y;
    if (dot(radialDirection, radialDirection) < 0.00001) {
        radialDirection = emitterRight;
    } else {
        radialDirection = normalize(radialDirection);
    }

    float spread = uniforms.shape.z * mix(0.45, 1.15, hash11(seed + 2.1));
    float3 velocityDirection = normalize(exhaustDir + radialDirection * spread);
    float speed = mix(uniforms.velocity.x, uniforms.velocity.y, hash11(seed + 3.3)) * (0.62 + throttle * 0.55);
    float life = mix(uniforms.lifeSize.x, uniforms.lifeSize.y, hash11(seed + 4.9));
    float size = mix(uniforms.lifeSize.z, uniforms.lifeSize.w, hash11(seed + 6.4));
    float drag = mix(uniforms.velocity.z, uniforms.velocity.w, hash11(seed + 7.6));
    float age = staggerAge ? hash11(seed + (float)id * 0.113) * life : 0.0;

    Particle particle;
    particle.positionSeed = float4(uniforms.emitterPosition.xyz + radialDirection * radius, seed);
    particle.velocityDrag = float4(velocityDirection * speed, drag);
    particle.color = uniforms.colorStart;
    particle.ageLifeSizeRandom = float4(age, life, size, hash11(seed + 9.2));

    if (age > 0.0) {
        particle.positionSeed.xyz += particle.velocityDrag.xyz * age * 0.75;
    }
    return particle;
}

static inline void shadeParticle(thread Particle &particle, constant ParticleUniforms &uniforms) {
    float normalizedAge = saturate(particle.ageLifeSizeRandom.x / max(particle.ageLifeSizeRandom.y, 0.0001));
    float fadeIn = smoothstep(0.0, max(uniforms.fade.x, 0.0001), normalizedAge);
    float fadeOut = 1.0 - smoothstep(uniforms.fade.y, 1.0, normalizedAge);
    float firstColorPhase = smoothstep(0.0, 0.42, normalizedAge);
    float secondColorPhase = smoothstep(0.34, 1.0, normalizedAge);

    particle.color = normalizedAge < 0.42
        ? mix(uniforms.colorStart, uniforms.colorMid, firstColorPhase)
        : mix(uniforms.colorMid, uniforms.colorEnd, secondColorPhase);
    particle.color.a *= fadeIn * fadeOut * uniforms.fade.z;
}

static inline bool particleDepthHit(float3 worldPosition,
                                    constant ParticleCollisionUniforms &collision,
                                    depth2d<float, access::sample> sceneDepth) {
    constexpr sampler nearestClamp(address::clamp_to_edge, filter::nearest);
    float4 clipPosition = collision.viewProjection * float4(worldPosition, 1.0);
    if (clipPosition.w <= 0.0001) {
        return false;
    }

    float3 ndc = clipPosition.xyz / clipPosition.w;
    if (ndc.z < 0.0 || ndc.z > 1.0) {
        return false;
    }

    float2 baseUV = float2(ndc.x * 0.5 + 0.5, 1.0 - (ndc.y * 0.5 + 0.5));
    if (!all(baseUV >= float2(0.0)) || !all(baseUV <= float2(1.0))) {
        return false;
    }

    float2 depthUV = clamp(baseUV * collision.uvTransform.xy + collision.uvTransform.zw, 0.0, 1.0);
    float surfaceDepth = sceneDepth.sample(nearestClamp, depthUV);
    if (surfaceDepth >= 0.999) {
        return false;
    }

    return ndc.z > surfaceDepth + collision.params.x;
}

static inline float3 reconstructDepthWorld(float2 baseUV,
                                           float depth,
                                           constant ParticleCollisionUniforms &collision) {
    float2 ndcXY = float2(baseUV.x * 2.0 - 1.0, (1.0 - baseUV.y) * 2.0 - 1.0);
    float4 world = collision.inverseViewProjection * float4(ndcXY, depth, 1.0);
    return world.xyz / max(abs(world.w), 0.0001);
}

static inline float3 depthSurfaceNormal(float3 worldPosition,
                                        float3 velocity,
                                        constant ParticleCollisionUniforms &collision,
                                        depth2d<float, access::sample> sceneDepth) {
    constexpr sampler nearestClamp(address::clamp_to_edge, filter::nearest);
    float4 clipPosition = collision.viewProjection * float4(worldPosition, 1.0);
    float3 ndc = clipPosition.xyz / max(clipPosition.w, 0.0001);
    float2 baseUV = clamp(float2(ndc.x * 0.5 + 0.5, 1.0 - (ndc.y * 0.5 + 0.5)), 0.0, 1.0);
    float2 texel = 1.0 / float2(max(sceneDepth.get_width(), 1u), max(sceneDepth.get_height(), 1u));

    float2 centerDepthUV = clamp(baseUV * collision.uvTransform.xy + collision.uvTransform.zw, 0.0, 1.0);
    float centerDepth = sceneDepth.sample(nearestClamp, centerDepthUV);
    float rightDepth = sceneDepth.sample(nearestClamp, clamp(centerDepthUV + float2(texel.x, 0.0), 0.0, 1.0));
    float upDepth = sceneDepth.sample(nearestClamp, clamp(centerDepthUV + float2(0.0, -texel.y), 0.0, 1.0));

    float2 rightBaseUV = clamp(baseUV + float2(texel.x / max(collision.uvTransform.x, 0.0001), 0.0), 0.0, 1.0);
    float2 upBaseUV = clamp(baseUV + float2(0.0, -texel.y / max(collision.uvTransform.y, 0.0001)), 0.0, 1.0);

    float3 center = reconstructDepthWorld(baseUV, centerDepth, collision);
    float3 right = reconstructDepthWorld(rightBaseUV, rightDepth, collision);
    float3 up = reconstructDepthWorld(upBaseUV, upDepth, collision);
    float3 normal = normalize(cross(right - center, up - center));
    if (!all(isfinite(normal)) || dot(normal, normal) < 0.25) {
        normal = -normalize(velocity);
    }
    if (dot(normal, velocity) > 0.0) {
        normal = -normal;
    }
    return normal;
}

static inline bool particlePlaneHit(float3 previousPosition,
                                    float3 currentPosition,
                                    float particleRadius,
                                    constant ParticleCollisionUniforms &collision,
                                    thread float3 &surfaceNormal) {
    if (collision.planeParams.w < 0.5) {
        return false;
    }

    float3 center = collision.planeCenter.xyz;
    float3 normal = normalize(collision.planeNormal.xyz);
    float3 tangent = normalize(collision.planeTangent.xyz);
    float3 bitangent = normalize(collision.planeBitangent.xyz);
    float previousDistance = dot(previousPosition - center, normal);
    float currentDistance = dot(currentPosition - center, normal);
    float radius = max(particleRadius * 0.45, 0.35);
    bool crossedPlane = (previousDistance <= radius && currentDistance >= -radius)
        || (previousDistance >= -radius && currentDistance <= radius);
    if (!crossedPlane) {
        return false;
    }

    float denominator = previousDistance - currentDistance;
    float t = abs(denominator) > 0.0001 ? clamp(previousDistance / denominator, 0.0, 1.0) : 1.0;
    float3 hitPosition = mix(previousPosition, currentPosition, t);
    float3 local = hitPosition - center;
    bool insideSurface = abs(dot(local, tangent)) <= collision.planeParams.x
        && abs(dot(local, bitangent)) <= collision.planeParams.y;
    if (!insideSurface) {
        return false;
    }

    surfaceNormal = normal;
    if (dot(surfaceNormal, currentPosition - previousPosition) > 0.0) {
        surfaceNormal = -surfaceNormal;
    }
    return true;
}

kernel void updateParticlePool(device Particle *particles [[buffer(0)]],
                               device atomic_uint *liveCounter [[buffer(1)]],
                               constant ParticleUniforms &uniforms [[buffer(2)]],
                               constant ParticleCollisionUniforms &collision [[buffer(3)]],
                               depth2d<float, access::sample> sceneDepth [[texture(0)]],
                               uint id [[thread_position_in_grid]]) {
    uint maxParticleCount = (uint)uniforms.timing.w;
    if (id >= maxParticleCount) {
        return;
    }

    float dt = clamp(uniforms.timing.x, 0.0, 1.0 / 20.0);
    float time = uniforms.timing.y;
    float throttle = saturate(uniforms.timing.z);
    float activeFraction = saturate(uniforms.shape.w * step(0.01, throttle));
    uint activeCount = max(1u, min(maxParticleCount, (uint)ceil((float)maxParticleCount * activeFraction)));
    if (id >= activeCount) {
        Particle deadParticle;
        deadParticle.positionSeed = float4(0.0);
        deadParticle.velocityDrag = float4(0.0);
        deadParticle.color = float4(0.0);
        deadParticle.ageLifeSizeRandom = float4(0.0);
        particles[id] = deadParticle;
        return;
    }

    Particle particle = particles[id];
    if (particle.ageLifeSizeRandom.y <= 0.0 || particle.ageLifeSizeRandom.x >= particle.ageLifeSizeRandom.y) {
        particle = makeParticle(id, uniforms, time, particle.ageLifeSizeRandom.y <= 0.0);
    }

    float normalizedAge = saturate(particle.ageLifeSizeRandom.x / max(particle.ageLifeSizeRandom.y, 0.0001));
    float seed = particle.positionSeed.w;
    float3 exhaustDir = normalize(uniforms.emitterDirection.xyz);
    float3 emitterRight = normalize(uniforms.emitterRight.xyz);
    float3 emitterUp = normalize(uniforms.emitterUp.xyz);
    float noiseA = sin(time * 11.0 + seed * 37.0 + normalizedAge * 4.0);
    float noiseB = cos(time * 8.0 + seed * 23.0 - normalizedAge * 5.0);
    float3 sideNoise = emitterRight * noiseA + emitterUp * noiseB;
    float3 previousPosition = particle.positionSeed.xyz;

    particle.velocityDrag.xyz += sideNoise * uniforms.behavior.y * dt * (0.18 + normalizedAge * 0.82);
    particle.velocityDrag.xyz += exhaustDir * uniforms.behavior.z * dt * (0.5 + throttle * 0.7);
    particle.velocityDrag.xyz *= max(0.0, 1.0 - particle.velocityDrag.w * dt);
    particle.positionSeed.xyz += particle.velocityDrag.xyz * dt;
    particle.ageLifeSizeRandom.x += dt;
    particle.ageLifeSizeRandom.z *= 1.0 + uniforms.behavior.x * dt;

    bool collided = false;
    if (collision.params.w > 0.5) {
        float3 currentPosition = particle.positionSeed.xyz;
        float3 midPosition = mix(previousPosition, currentPosition, 0.5);
        float3 analyticNormal = float3(0.0, 1.0, 0.0);
        bool analyticHit = particlePlaneHit(
            previousPosition,
            currentPosition,
            particle.ageLifeSizeRandom.z,
            collision,
            analyticNormal
        );
        bool currentHit = particleDepthHit(currentPosition, collision, sceneDepth);
        bool midHit = particleDepthHit(midPosition, collision, sceneDepth);

        if (analyticHit || currentHit || midHit) {
            collided = true;
            float3 surfaceNormal = analyticHit
                ? analyticNormal
                : depthSurfaceNormal(
                    currentHit ? currentPosition : midPosition,
                    particle.velocityDrag.xyz,
                    collision,
                    sceneDepth
                );
            float3 velocity = particle.velocityDrag.xyz;
            float normalSpeed = dot(velocity, surfaceNormal);
            float3 tangentVelocity = velocity - surfaceNormal * normalSpeed;
            particle.positionSeed.xyz = previousPosition + surfaceNormal * max(particle.ageLifeSizeRandom.z * 0.55, 0.75);
            particle.velocityDrag.xyz = tangentVelocity * 0.55 + reflect(velocity, surfaceNormal) * collision.params.y;
            particle.ageLifeSizeRandom.x = min(
                particle.ageLifeSizeRandom.y,
                particle.ageLifeSizeRandom.x + dt * collision.params.z
            );
        }
    }

    shadeParticle(particle, uniforms);
    if (!collided && (particle.ageLifeSizeRandom.x >= particle.ageLifeSizeRandom.y || particle.color.a <= 0.001)) {
        particle = makeParticle(id, uniforms, time + seed, false);
        shadeParticle(particle, uniforms);
    }

    particles[id] = particle;
    atomic_fetch_add_explicit(&liveCounter[0], 1, memory_order_relaxed);
}

kernel void buildParticleSortKeys(device const Particle *particles [[buffer(0)]],
                                  device ParticleSortKey *sortKeys [[buffer(1)]],
                                  constant ParticleUniforms &uniforms [[buffer(2)]],
                                  constant float4x4 &view [[buffer(3)]],
                                  constant uint &sortKeyCount [[buffer(4)]],
                                  uint id [[thread_position_in_grid]]) {
    if (id >= sortKeyCount) {
        return;
    }

    uint maxParticleCount = (uint)uniforms.timing.w;
    if (id >= maxParticleCount) {
        sortKeys[id] = makeSortKey(-FLT_MAX, id);
        return;
    }

    Particle particle = particles[id];
    bool alive = particle.ageLifeSizeRandom.y > 0.0
        && particle.ageLifeSizeRandom.x < particle.ageLifeSizeRandom.y
        && particle.color.a > 0.001;
    if (!alive) {
        sortKeys[id] = makeSortKey(-FLT_MAX, id);
        return;
    }

    float4 viewPosition = view * float4(particle.positionSeed.xyz, 1.0);
    sortKeys[id] = makeSortKey(-viewPosition.z, id);
}

kernel void sortParticleKeys(device ParticleSortKey *sortKeys [[buffer(0)]],
                             constant SortParams &params [[buffer(1)]],
                             uint id [[thread_position_in_grid]]) {
    if (id >= params.count) {
        return;
    }

    uint pairIndex = id ^ params.pass;
    if (pairIndex <= id || pairIndex >= params.count) {
        return;
    }

    ParticleSortKey left = sortKeys[id];
    ParticleSortKey right = sortKeys[pairIndex];
    bool descendingHalf = (id & params.stage) == 0;
    bool shouldSwap = descendingHalf
        ? left.depth < right.depth
        : left.depth > right.depth;
    if (shouldSwap) {
        sortKeys[id] = right;
        sortKeys[pairIndex] = left;
    }
}

struct ParticleVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float stretch;
};

vertex ParticleVertexOut vertexParticle(uint vertexID [[vertex_id]],
                                        uint instanceID [[instance_id]],
                                        device const Particle *particles [[buffer(0)]],
                                        device const ParticleSortKey *sortKeys [[buffer(1)]],
                                        constant ParticleUniforms &uniforms [[buffer(2)]],
                                        constant float4x4 &view [[buffer(3)]],
                                        constant float4x4 &projection [[buffer(4)]]) {
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(1.0, -1.0), float2(1.0, 1.0), float2(-1.0, 1.0)
    };

    ParticleVertexOut out;
    ParticleSortKey sortKey = sortKeys[instanceID];
    if (sortKey.depth <= -FLT_MAX * 0.5 || sortKey.particleIndex >= (uint)uniforms.timing.w) {
        out.position = float4(2.0, 2.0, 1.0, 1.0);
        out.uv = float2(0.0);
        out.color = float4(0.0);
        out.stretch = 1.0;
        return out;
    }

    Particle particle = particles[sortKey.particleIndex];
    if (particle.ageLifeSizeRandom.y <= 0.0 ||
        particle.ageLifeSizeRandom.x >= particle.ageLifeSizeRandom.y ||
        particle.color.a <= 0.001) {
        out.position = float4(2.0, 2.0, 1.0, 1.0);
        out.uv = float2(0.0);
        out.color = float4(0.0);
        out.stretch = 1.0;
        return out;
    }

    float2 corner = corners[vertexID];
    float normalizedAge = saturate(particle.ageLifeSizeRandom.x / max(particle.ageLifeSizeRandom.y, 0.0001));
    float size = particle.ageLifeSizeRandom.z;
    size *= mix(0.34, 1.0, smoothstep(0.0, 0.18, normalizedAge));
    size *= mix(1.0, 0.48, smoothstep(0.78, 1.0, normalizedAge));

    float3 right = normalize(uniforms.cameraRight.xyz);
    float3 up = normalize(uniforms.cameraUp.xyz);
    float stretch = max(uniforms.behavior.w, 1.0);
    float3 viewForward = normalize(cross(right, up));
    float3 velocityDir = normalize(particle.velocityDrag.xyz + uniforms.emitterDirection.xyz * 0.001);
    float3 stretchAxis = velocityDir - viewForward * dot(velocityDir, viewForward);
    if (dot(stretchAxis, stretchAxis) < 0.0001) {
        stretchAxis = up;
    } else {
        stretchAxis = normalize(stretchAxis);
    }
    float3 crossAxis = normalize(cross(viewForward, stretchAxis));
    float useVelocityAxes = step(1.05, stretch);
    float3 horizontalAxis = normalize(mix(right, crossAxis, useVelocityAxes));
    float3 verticalAxis = normalize(mix(up, stretchAxis, useVelocityAxes));

    float3 worldPosition = particle.positionSeed.xyz
        + horizontalAxis * corner.x * size
        + verticalAxis * corner.y * size * stretch;

    out.position = projection * view * float4(worldPosition, 1.0);
    out.uv = corner * 0.5 + 0.5;
    out.color = particle.color;
    out.stretch = stretch;
    return out;
}

fragment float4 fragmentParticle(ParticleVertexOut in [[stage_in]],
                                 constant ParticleUniforms &uniforms [[buffer(0)]]) {
    (void)uniforms;
    float2 centeredUV = in.uv * 2.0 - 1.0;
    float radiusSquared = dot(centeredUV, centeredUV);
    float softCircle = smoothstep(1.0, 0.08, radiusSquared);
    if (softCircle <= 0.001 || in.color.a <= 0.001) {
        discard_fragment();
    }

    float3 color = in.color.rgb;
    if (in.stretch > 1.5) {
        float core = smoothstep(0.24, 0.0, radiusSquared);
        color += core * float3(1.35, 0.72, 0.16);
    }

    return float4(color, in.color.a * softCircle);
}
