#include <metal_stdlib>
using namespace metal;

// Geometry pass input layout from CPU vertex descriptor.
struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float3 normal   [[attribute(2)]];
};

struct VSOutGeo {
    float4 position [[position]];
    float3 worldNormal;
    float2 uv;
};

// Helpers for proper normal transformation (inverse-transpose of model matrix).
static inline float3x3 inverse3x3(float3x3 m) {
    float3 c0 = cross(m[1], m[2]);
    float3 c1 = cross(m[2], m[0]);
    float3 c2 = cross(m[0], m[1]);
    float invDet = 1.0 / dot(c2, m[2]);
    return float3x3(c0 * invDet, c1 * invDet, c2 * invDet);
}

static inline float3x3 normalMatrix(float4x4 model) {
    float3x3 upper = float3x3(model[0].xyz, model[1].xyz, model[2].xyz);
    return transpose(inverse3x3(upper));
}

vertex VSOutGeo vertexGeometry(VertexIn in [[stage_in]],
                               constant float4x4 &model [[buffer(1)]],
                               constant float4x4 &view [[buffer(2)]],
                               constant float4x4 &proj [[buffer(3)]]) {
    // Deferred geometry stage: output clip-space position + world-space attributes.
    VSOutGeo out;
    float4 worldPosition = model * float4(in.position, 1.0);
    out.position = proj * view * worldPosition;
    out.worldNormal = normalize(normalMatrix(model) * in.normal);
    out.uv = in.texCoord;
    return out;
}

struct GBufferOut {
    float4 albedo [[color(0)]];
    float4 normal [[color(1)]];
};

fragment GBufferOut fragmentGeometry(VSOutGeo in [[stage_in]],
                                     constant float &specularStrength [[buffer(0)]],
                                     texture2d<float> albedoTex [[texture(0)]]) {
    // Write material properties into MRT G-Buffer attachments.
    constexpr sampler linearRepeat(address::repeat, filter::linear);
    GBufferOut out;
    if (albedoTex.get_width() == 0 || albedoTex.get_height() == 0) {
        out.albedo = float4(1.0, 1.0, 1.0, saturate(specularStrength));
    } else {
        out.albedo = float4(albedoTex.sample(linearRepeat, in.uv).rgb, saturate(specularStrength));
    }
    out.normal = float4(normalize(in.worldNormal), 1.0);
    return out;
}

struct VSOutFullscreen {
    float4 position [[position]];
    float2 uv;
};

vertex VSOutFullscreen vertexFullscreen(uint vertexID [[vertex_id]]) {
    // Fullscreen single-triangle generator for the lighting resolve pass.
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    VSOutFullscreen out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = 0.5 * (positions[vertexID] + 1.0);
    return out;
}

struct MtlDirectionalLight {
    float4 direction;
    float4 colorIntensity;
};

struct MtlPointLight {
    float4 positionRadius;
    float4 colorIntensity;
};

struct MtlSpotLight {
    float4 positionRadius;
    float4 directionInnerCos;
    float4 colorIntensity;
    float4 params;
};

float3 applyDirectional(float3 N, float3 V, float3 albedo, float specularStrength, constant MtlDirectionalLight &L) {
    // Classic Blinn-Phong directional contribution.
    float3 Ld = normalize(-L.direction.xyz);
    float NdotL = max(dot(N, Ld), 0.0);
    float intensity = L.colorIntensity.w;
    float3 color = L.colorIntensity.xyz;

    float3 diffuse = albedo * color * (intensity * NdotL);
    float3 H = normalize(Ld + V);
    float specular = pow(max(dot(N, H), 0.0), 32.0) * intensity * specularStrength;
    return diffuse + specular;
}

float3 applyPoint(float3 P, float3 N, float3 V, float3 albedo, float specularStrength, device const MtlPointLight &L) {
    // Point light with radius-based attenuation.
    float3 Ld = L.positionRadius.xyz - P;
    float dist = max(length(Ld), 1e-4);
    Ld /= dist;

    float radius = max(L.positionRadius.w, 1e-3);
    float intensity = L.colorIntensity.w;
    float3 color = L.colorIntensity.xyz;

    float att = saturate(1.0 - dist / radius);
    float NdotL = max(dot(N, Ld), 0.0);

    float3 diffuse = albedo * color * (intensity * NdotL * att);
    float3 H = normalize(Ld + V);
    float specular = pow(max(dot(N, H), 0.0), 32.0) * intensity * att * specularStrength;
    return diffuse + specular;
}

float3 applySpot(float3 P, float3 N, float3 V, float3 albedo, float specularStrength, device const MtlSpotLight &L) {
    // Spot light with cone + distance attenuation.
    float3 Ld = L.positionRadius.xyz - P;
    float dist = max(length(Ld), 1e-4);
    Ld /= dist;

    float radius = max(L.positionRadius.w, 1e-3);
    float innerCos = L.directionInnerCos.w;
    float outerCos = L.params.x;
    float intensity = L.colorIntensity.w;

    float cone = dot(-Ld, normalize(L.directionInnerCos.xyz));
    float coneAtt = smoothstep(outerCos, innerCos, cone);
    float distAtt = saturate(1.0 - dist / radius);
    float att = coneAtt * distAtt;

    float NdotL = max(dot(N, Ld), 0.0);
    float3 diffuse = albedo * L.colorIntensity.xyz * (intensity * NdotL * att);
    float3 H = normalize(Ld + V);
    float specular = pow(max(dot(N, H), 0.0), 32.0) * intensity * att * specularStrength;
    return diffuse + specular;
}

fragment float4 fragmentLighting(VSOutFullscreen in [[stage_in]],
                                 texture2d<float> gAlbedo [[texture(0)]],
                                 texture2d<float> gNormal [[texture(1)]],
                                 depth2d<float> gDepth [[texture(2)]],
                                 constant float3 &eyePos [[buffer(0)]],
                                 constant MtlDirectionalLight &dLight [[buffer(1)]],
                                 constant uint &pointCount [[buffer(2)]],
                                 const device MtlPointLight *pointLights [[buffer(3)]],
                                 constant uint &spotCount [[buffer(4)]],
                                 const device MtlSpotLight *spotLights [[buffer(5)]],
                                 constant float4x4 &invView [[buffer(6)]],
                                 constant float4x4 &invProj [[buffer(7)]],
                                 constant int &previewMode [[buffer(8)]]) {
    // Deferred lighting stage:
    // 1) read packed G-Buffer,
    // 2) reconstruct world position from depth,
    // 3) accumulate all lights,
    // 4) optionally output debug visualizations.
    constexpr sampler nearestClamp(address::clamp_to_edge, filter::nearest);

    float2 uv = clamp(in.uv, 0.0, 1.0);
    float4 gAlbedoSample = gAlbedo.sample(nearestClamp, uv);
    float3 albedo = gAlbedoSample.rgb;
    float specularStrength = gAlbedoSample.a;
    float3 N = normalize(gNormal.sample(nearestClamp, uv).xyz);

    float depth = gDepth.sample(nearestClamp, uv);
    if (depth >= 1.0) {
        return float4(0.03 * albedo, 1.0);
    }

    float2 ndcXY = float2(uv.x * 2.0 - 1.0, (1.0 - uv.y) * 2.0 - 1.0);
    float ndcZ = depth;
    float4 clipPos = float4(ndcXY, ndcZ, 1.0);
    float4 viewPos = invProj * clipPos;
    viewPos /= max(viewPos.w, 1e-6);

    float4 worldPos = invView * float4(viewPos.xyz, 1.0);
    float3 P = worldPos.xyz;
    float3 V = normalize(eyePos - P);

    if (previewMode == 1) {
        return float4(albedo, 1.0);
    }
    if (previewMode == 2) {
        return float4(N * 0.5 + 0.5, 1.0);
    }
    if (previewMode == 3) {
        return float4(depth, depth, depth, 1.0);
    }
    if (previewMode == 4) {
        return float4(fract(abs(P) * 0.05), 1.0);
    }

    // Base ambient + dynamic light accumulation.
    float3 color = 0.03 * albedo;
    color += applyDirectional(N, V, albedo, specularStrength, dLight);

    for (uint i = 0; i < pointCount; ++i) {
        color += applyPoint(P, N, V, albedo, specularStrength, pointLights[i]);
    }
    for (uint i = 0; i < spotCount; ++i) {
        color += applySpot(P, N, V, albedo, specularStrength, spotLights[i]);
    }

    return float4(color, 1.0);
}
