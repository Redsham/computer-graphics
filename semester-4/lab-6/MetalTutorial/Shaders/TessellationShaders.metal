#include <metal_stdlib>
using namespace metal;

struct GBufferOut {
    float4 albedo [[color(0)]];
    float4 normal [[color(1)]];
};

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

struct TerrainControlPoint {
    float3 position;
    float2 uv;
};

struct TessellationPatchInfo {
    float3 patchCenter;
    float minFactor;
    float maxFactor;
    float minDistance;
    float maxDistance;
    float3 edgeMidpoint0;
    float3 edgeMidpoint1;
    float3 edgeMidpoint2;
    float3 edgeMidpoint3;
};

struct TessellationSurfaceParams {
    float displacementScale;
    float2 uvScale;
    float normalStrength;
    float _padding;
};

struct TerrainTessellationFactors {
    half edgeTessellationFactor[4];
    half insideTessellationFactor[2];
};

struct VSOutTerrain {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 uv;
};

static inline TerrainControlPoint bilerpControlPoints(const device TerrainControlPoint *controlPoints,
                                                      uint patchBase,
                                                      float2 uv) {
    TerrainControlPoint cp00 = controlPoints[patchBase + 0];
    TerrainControlPoint cp10 = controlPoints[patchBase + 1];
    TerrainControlPoint cp01 = controlPoints[patchBase + 2];
    TerrainControlPoint cp11 = controlPoints[patchBase + 3];

    TerrainControlPoint result;
    result.position = mix(mix(cp00.position, cp10.position, uv.x), mix(cp01.position, cp11.position, uv.x), uv.y);
    result.uv = mix(mix(cp00.uv, cp10.uv, uv.x), mix(cp01.uv, cp11.uv, uv.x), uv.y);
    return result;
}

static inline float sampleTerrainHeight(texture2d<float> displacementTex,
                                        sampler displacementSampler,
                                        float2 uv,
                                        float displacementScale) {
    if (displacementTex.get_width() == 0 || displacementTex.get_height() == 0) {
        return 0.0;
    }
    return (displacementTex.sample(displacementSampler, uv).r * 2.0 - 1.0) * displacementScale;
}

static inline float3 terrainObjectPosition(const device TerrainControlPoint *controlPoints,
                                           uint patchBase,
                                           float2 patchUV,
                                           float2 scaledUV,
                                           texture2d<float> displacementTex,
                                           sampler displacementSampler,
                                           float displacementScale) {
    TerrainControlPoint surfacePoint = bilerpControlPoints(controlPoints, patchBase, patchUV);
    return surfacePoint.position + float3(0.0, sampleTerrainHeight(displacementTex, displacementSampler, scaledUV, displacementScale), 0.0);
}

static inline float quantizedTessellationFactor(float distance,
                                                float minFactor,
                                                float maxFactor,
                                                float minDistance,
                                                float maxDistance) {
    float range = max(maxDistance - minDistance, 1.0);
    float t = saturate((distance - minDistance) / range);
    // Exponential falloff keeps detail near the camera and drops it off much faster in the distance.
    float expFalloff = (exp2(-6.0 * t) - exp2(-6.0)) / (1.0 - exp2(-6.0));
    float factor = mix(minFactor, maxFactor, saturate(expFalloff));
    factor = clamp(round(factor * 0.5) * 2.0, minFactor, maxFactor);
    return max(factor, minFactor);
}

kernel void computeTerrainTessellationFactors(const device TessellationPatchInfo *patchInfos [[buffer(0)]],
                                              device TerrainTessellationFactors *factors [[buffer(1)]],
                                              constant float3 &cameraPos [[buffer(2)]],
                                              uint patchID [[thread_position_in_grid]]) {
    TessellationPatchInfo info = patchInfos[patchID];
    float insideFactor = quantizedTessellationFactor(length(cameraPos - info.patchCenter),
                                                     info.minFactor,
                                                     info.maxFactor,
                                                     info.minDistance,
                                                     info.maxDistance);

    factors[patchID].edgeTessellationFactor[0] = half(quantizedTessellationFactor(length(cameraPos - info.edgeMidpoint0),
                                                                                  info.minFactor,
                                                                                  info.maxFactor,
                                                                                  info.minDistance,
                                                                                  info.maxDistance));
    factors[patchID].edgeTessellationFactor[1] = half(quantizedTessellationFactor(length(cameraPos - info.edgeMidpoint1),
                                                                                  info.minFactor,
                                                                                  info.maxFactor,
                                                                                  info.minDistance,
                                                                                  info.maxDistance));
    factors[patchID].edgeTessellationFactor[2] = half(quantizedTessellationFactor(length(cameraPos - info.edgeMidpoint2),
                                                                                  info.minFactor,
                                                                                  info.maxFactor,
                                                                                  info.minDistance,
                                                                                  info.maxDistance));
    factors[patchID].edgeTessellationFactor[3] = half(quantizedTessellationFactor(length(cameraPos - info.edgeMidpoint3),
                                                                                  info.minFactor,
                                                                                  info.maxFactor,
                                                                                  info.minDistance,
                                                                                  info.maxDistance));
    factors[patchID].insideTessellationFactor[0] = half(insideFactor);
    factors[patchID].insideTessellationFactor[1] = half(insideFactor);
}

[[patch(quad, 4)]]
vertex VSOutTerrain vertexTerrainTessellated(uint patchID [[patch_id]],
                                             float2 positionInPatch [[position_in_patch]],
                                             const device TerrainControlPoint *controlPoints [[buffer(0)]],
                                             constant float4x4 &model [[buffer(1)]],
                                             constant float4x4 &view [[buffer(2)]],
                                             constant float4x4 &proj [[buffer(3)]],
                                             constant TessellationSurfaceParams &surfaceParams [[buffer(4)]],
                                             texture2d<float> displacementTex [[texture(0)]]) {
    constexpr sampler displacementSampler(address::repeat, filter::linear);
    VSOutTerrain out;

    uint patchBase = patchID * 4;
    float2 scaledUV = bilerpControlPoints(controlPoints, patchBase, positionInPatch).uv * surfaceParams.uvScale;

    float texelU = displacementTex.get_width() > 0 ? 1.0 / float(displacementTex.get_width()) : 0.001;
    float texelV = displacementTex.get_height() > 0 ? 1.0 / float(displacementTex.get_height()) : 0.001;
    float2 uvDX = float2(texelU, 0.0);
    float2 uvDY = float2(0.0, texelV);
    float2 patchStep = float2(texelU / max(surfaceParams.uvScale.x, 1e-3),
                              texelV / max(surfaceParams.uvScale.y, 1e-3));
    float2 patchUVx0 = clamp(positionInPatch - float2(patchStep.x, 0.0), 0.0, 1.0);
    float2 patchUVx1 = clamp(positionInPatch + float2(patchStep.x, 0.0), 0.0, 1.0);
    float2 patchUVy0 = clamp(positionInPatch - float2(0.0, patchStep.y), 0.0, 1.0);
    float2 patchUVy1 = clamp(positionInPatch + float2(0.0, patchStep.y), 0.0, 1.0);

    float3 P = terrainObjectPosition(controlPoints, patchBase, positionInPatch, scaledUV, displacementTex, displacementSampler, surfaceParams.displacementScale);
    float3 Px0 = terrainObjectPosition(controlPoints, patchBase, patchUVx0, scaledUV - uvDX, displacementTex, displacementSampler, surfaceParams.displacementScale);
    float3 Px1 = terrainObjectPosition(controlPoints, patchBase, patchUVx1, scaledUV + uvDX, displacementTex, displacementSampler, surfaceParams.displacementScale);
    float3 Py0 = terrainObjectPosition(controlPoints, patchBase, patchUVy0, scaledUV - uvDY, displacementTex, displacementSampler, surfaceParams.displacementScale);
    float3 Py1 = terrainObjectPosition(controlPoints, patchBase, patchUVy1, scaledUV + uvDY, displacementTex, displacementSampler, surfaceParams.displacementScale);

    float3 tangentX = Px1 - Px0;
    float3 tangentY = Py1 - Py0;
    float3 objectNormal = normalize(cross(tangentY, tangentX));
    float4 worldPosition = model * float4(P, 1.0);
    float3x3 worldNormalMatrix = normalMatrix(model);

    out.position = proj * view * worldPosition;
    out.worldPosition = worldPosition.xyz;
    out.worldNormal = normalize(worldNormalMatrix * objectNormal);
    out.uv = scaledUV;
    return out;
}

fragment GBufferOut fragmentTerrainGeometry(VSOutTerrain in [[stage_in]],
                                            constant float &specularStrength [[buffer(0)]],
                                            constant TessellationSurfaceParams &surfaceParams [[buffer(1)]],
                                            texture2d<float> albedoTex [[texture(0)]],
                                            texture2d<float> normalTex [[texture(1)]]) {
    constexpr sampler linearRepeat(address::repeat, filter::linear);
    GBufferOut out;
    if (albedoTex.get_width() == 0 || albedoTex.get_height() == 0) {
        out.albedo = float4(1.0, 1.0, 1.0, saturate(specularStrength));
    } else {
        out.albedo = float4(albedoTex.sample(linearRepeat, in.uv).rgb, saturate(specularStrength));
    }
    float3 N = normalize(in.worldNormal);
    if (surfaceParams.normalStrength > 0.0 &&
        normalTex.get_width() > 0 &&
        normalTex.get_height() > 0) {
        float3 dPdx = dfdx(in.worldPosition);
        float3 dPdy = dfdy(in.worldPosition);
        float2 dUVdx = dfdx(in.uv);
        float2 dUVdy = dfdy(in.uv);
        float3 T = normalize(dPdx * dUVdy.y - dPdy * dUVdx.y);
        float3 B = normalize(-dPdx * dUVdy.x + dPdy * dUVdx.x);
        float3x3 tbn = float3x3(T, B, N);
        float3 normalTS = normalize(normalTex.sample(linearRepeat, in.uv).xyz * 2.0 - 1.0);
        float3 mappedNormal = normalize(tbn * normalTS);
        N = normalize(mix(N, mappedNormal, saturate(surfaceParams.normalStrength)));
    }
    out.normal = float4(N, 1.0);
    return out;
}
