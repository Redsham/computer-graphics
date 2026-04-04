#include <metal_stdlib>
using namespace metal;

struct GBufferOut {
    float4 albedo [[color(0)]];
    float4 normal [[color(1)]];
    float4 material [[color(2)]];
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
    float2 patchMin;
    float2 patchMax;
};

struct TessellationLODParams {
    float2 boundsMin;
    float2 boundsMax;
    float minFactor;
    float maxFactor;
    float minDistance;
    float maxDistance;
};

struct TessellationSurfaceParams {
    float displacementScale;
    float2 uvScale;
    float normalStrength;
    float time;
    float waveAmplitude;
    float waveFrequency;
    float waveSpeed;
    float _padding;
};

struct MaterialParams {
    float specularStrength;
    float roughness;
    float opacity;
    float _padding;
};

struct MtlDirectionalLight {
    float4 direction;
    float4 colorIntensity;
};

struct MtlAmbientLight {
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

static inline float3 applyDirectional(float3 N, float3 V, float3 albedo, float specularStrength, float roughness, constant MtlDirectionalLight &L) {
    float3 Ld = normalize(-L.direction.xyz);
    float NdotL = max(dot(N, Ld), 0.0);
    float intensity = L.colorIntensity.w;
    float3 color = L.colorIntensity.xyz;
    float3 diffuse = albedo * color * (intensity * NdotL);
    float3 H = normalize(Ld + V);
    float shininess = mix(96.0, 6.0, saturate(roughness));
    float specular = pow(max(dot(N, H), 0.0), shininess) * intensity * specularStrength;
    return diffuse + specular;
}

static inline float3 applyPoint(float3 P, float3 N, float3 V, float3 albedo, float specularStrength, float roughness, device const MtlPointLight &L) {
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
    float shininess = mix(96.0, 6.0, saturate(roughness));
    float specular = pow(max(dot(N, H), 0.0), shininess) * intensity * att * specularStrength;
    return diffuse + specular;
}

static inline float3 applySpot(float3 P, float3 N, float3 V, float3 albedo, float specularStrength, float roughness, device const MtlSpotLight &L) {
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
    float shininess = mix(96.0, 6.0, saturate(roughness));
    float specular = pow(max(dot(N, H), 0.0), shininess) * intensity * att * specularStrength;
    return diffuse + specular;
}

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
                                        float displacementScale,
                                        constant TessellationSurfaceParams &surfaceParams) {
    float wavePhaseX = uv.x * surfaceParams.waveFrequency + surfaceParams.time * surfaceParams.waveSpeed;
    float wavePhaseY = uv.y * (surfaceParams.waveFrequency * 1.37) - surfaceParams.time * (surfaceParams.waveSpeed * 0.73);
    float animatedWave = (sin(wavePhaseX) + cos(wavePhaseY)) * 0.5 * surfaceParams.waveAmplitude;
    if (displacementTex.get_width() == 0 || displacementTex.get_height() == 0) {
        return animatedWave;
    }
    return (displacementTex.sample(displacementSampler, uv).r * 2.0 - 1.0) * displacementScale + animatedWave;
}

static inline float3 terrainObjectPosition(const device TerrainControlPoint *controlPoints,
                                           uint patchBase,
                                           float2 patchUV,
                                           float2 scaledUV,
                                           texture2d<float> displacementTex,
                                           sampler displacementSampler,
                                           constant TessellationSurfaceParams &surfaceParams) {
    TerrainControlPoint surfacePoint = bilerpControlPoints(controlPoints, patchBase, patchUV);
    return surfacePoint.position + float3(0.0, sampleTerrainHeight(displacementTex, displacementSampler, scaledUV, surfaceParams.displacementScale, surfaceParams), 0.0);
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

static inline float3 closestPointOnPatch(float3 point, float2 patchMin, float2 patchMax) {
    return float3(clamp(point.x, patchMin.x, patchMax.x),
                  0.0,
                  clamp(point.z, patchMin.y, patchMax.y));
}

static inline float3 closestPointOnEdge(float3 point, float3 edgeStart, float3 edgeEnd) {
    float3 edge = edgeEnd - edgeStart;
    float edgeLengthSquared = max(dot(edge, edge), 1e-6);
    float t = saturate(dot(point - edgeStart, edge) / edgeLengthSquared);
    return edgeStart + edge * t;
}

kernel void computeTerrainTessellationFactors(const device TessellationPatchInfo *patchInfos [[buffer(0)]],
                                              device TerrainTessellationFactors *factors [[buffer(1)]],
                                              constant float3 &cameraPos [[buffer(2)]],
                                              constant float4x4 &inverseModel [[buffer(3)]],
                                              constant TessellationLODParams &lodParams [[buffer(4)]],
                                              uint patchID [[thread_position_in_grid]]) {
    (void)patchInfos;
    float3 cameraLocal = (inverseModel * float4(cameraPos, 1.0)).xyz;
    float3 planeClosest = closestPointOnPatch(cameraLocal, lodParams.boundsMin, lodParams.boundsMax);
    float distanceToPlane = length(cameraLocal - planeClosest);
    half tessellationFactor = half(quantizedTessellationFactor(distanceToPlane,
                                                               lodParams.minFactor,
                                                               lodParams.maxFactor,
                                                               lodParams.minDistance,
                                                               lodParams.maxDistance));

    factors[patchID].edgeTessellationFactor[0] = tessellationFactor;
    factors[patchID].edgeTessellationFactor[1] = tessellationFactor;
    factors[patchID].edgeTessellationFactor[2] = tessellationFactor;
    factors[patchID].edgeTessellationFactor[3] = tessellationFactor;
    factors[patchID].insideTessellationFactor[0] = tessellationFactor;
    factors[patchID].insideTessellationFactor[1] = tessellationFactor;
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

    float3 P = terrainObjectPosition(controlPoints, patchBase, positionInPatch, scaledUV, displacementTex, displacementSampler, surfaceParams);
    float3 Px0 = terrainObjectPosition(controlPoints, patchBase, patchUVx0, scaledUV - uvDX, displacementTex, displacementSampler, surfaceParams);
    float3 Px1 = terrainObjectPosition(controlPoints, patchBase, patchUVx1, scaledUV + uvDX, displacementTex, displacementSampler, surfaceParams);
    float3 Py0 = terrainObjectPosition(controlPoints, patchBase, patchUVy0, scaledUV - uvDY, displacementTex, displacementSampler, surfaceParams);
    float3 Py1 = terrainObjectPosition(controlPoints, patchBase, patchUVy1, scaledUV + uvDY, displacementTex, displacementSampler, surfaceParams);

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
                                            constant MaterialParams &materialParams [[buffer(0)]],
                                            constant TessellationSurfaceParams &surfaceParams [[buffer(1)]],
                                            texture2d<float> albedoTex [[texture(0)]],
                                            texture2d<float> normalTex [[texture(1)]]) {
    constexpr sampler linearRepeat(address::repeat, filter::linear);
    GBufferOut out;
    if (albedoTex.get_width() == 0 || albedoTex.get_height() == 0) {
        out.albedo = float4(1.0, 1.0, 1.0, 1.0);
    } else {
        out.albedo = float4(albedoTex.sample(linearRepeat, in.uv).rgb, 1.0);
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
    out.normal = float4(N, saturate(materialParams.roughness));
    out.material = float4(saturate(materialParams.specularStrength), saturate(materialParams.opacity), 0.0, 0.0);
    return out;
}

fragment float4 fragmentTerrainTransparent(VSOutTerrain in [[stage_in]],
                                           constant float3 &eyePos [[buffer(0)]],
                                           constant MtlAmbientLight &ambientLight [[buffer(1)]],
                                           constant MtlDirectionalLight &dLight [[buffer(2)]],
                                           constant uint &pointCount [[buffer(3)]],
                                           const device MtlPointLight *pointLights [[buffer(4)]],
                                           constant uint &spotCount [[buffer(5)]],
                                           const device MtlSpotLight *spotLights [[buffer(6)]],
                                           constant MaterialParams &materialParams [[buffer(7)]],
                                           constant TessellationSurfaceParams &surfaceParams [[buffer(8)]],
                                           constant int &previewMode [[buffer(9)]],
                                           texture2d<float> albedoTex [[texture(0)]],
                                           texture2d<float> normalTex [[texture(1)]]) {
    constexpr sampler linearRepeat(address::repeat, filter::linear);
    float3 albedo = albedoTex.get_width() > 0 && albedoTex.get_height() > 0
        ? albedoTex.sample(linearRepeat, in.uv).rgb
        : float3(1.0);

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

    float roughness = saturate(materialParams.roughness);
    float opacity = saturate(materialParams.opacity);
    float specularStrength = saturate(materialParams.specularStrength);
    float3 V = normalize(eyePos - in.worldPosition);
    float fresnel = pow(1.0 - saturate(dot(N, V)), 3.0);

    if (previewMode == 1) {
        return float4(albedo, opacity);
    }
    if (previewMode == 2) {
        return float4(N * 0.5 + 0.5, opacity);
    }
    if (previewMode == 3) {
        float linearDepth = length(eyePos - in.worldPosition);
        float debugDepth = saturate(linearDepth / 5000.0);
        return float4(debugDepth, debugDepth, debugDepth, opacity);
    }
    if (previewMode == 4) {
        return float4(fract(abs(in.worldPosition) * 0.05), opacity);
    }
    if (previewMode == 5) {
        return float4(0.92, 0.96, 1.0, max(opacity, 0.85));
    }

    float3 color = albedo * ambientLight.colorIntensity.xyz * ambientLight.colorIntensity.w;
    color += applyDirectional(N, V, albedo, specularStrength, roughness, dLight);
    for (uint i = 0; i < pointCount; ++i) {
        color += applyPoint(in.worldPosition, N, V, albedo, specularStrength, roughness, pointLights[i]);
    }
    for (uint i = 0; i < spotCount; ++i) {
        color += applySpot(in.worldPosition, N, V, albedo, specularStrength, roughness, spotLights[i]);
    }

    float glassAlpha = clamp(opacity + fresnel * 0.18, 0.0, 1.0);
    return float4(color, glassAlpha);
}
