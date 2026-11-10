#include "../../GPUShared/include/GPUShared.h"

// MARK: - Forward lighting

struct VertexOutput {
    float4 position [[position]];
    float3 normal;
    float3 color;
};

vertex VertexOutput forwardVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                  const device GPUVertex *vertices [[buffer(GPUVertexBinding)]],
                                  constant GPUFrame &frame [[buffer(GPUFrameBinding)]],
                                  const device GPUObject *objects [[buffer(GPUObjectBinding)]]) {
    GPUObject object = objects[instanceID];
    VertexOutput out;
    out.position = frame.viewProjection * object.model * vertices[vertexID].position;
    out.normal = (object.normalMatrix * float4(vertices[vertexID].normal.xyz, 0)).xyz;
    out.color = object.baseColor.xyz;
    return out;
}

fragment float4 forwardFragment(VertexOutput in [[stage_in]],
                                constant GPUFrame &frame [[buffer(GPUFrameBinding)]]) {
    float diffuse = max(dot(normalize(in.normal), -normalize(frame.lightDirection.xyz)), 0.0);
    return float4(in.color * (0.12 + diffuse * frame.lightColor.xyz), 1);
}

// MARK: - Tone mapping and output

struct ScreenOutput {
    float4 position [[position]];
};

vertex ScreenOutput outputVertex(uint id [[vertex_id]]) {
    float2 positions[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    return {float4(positions[id], 0, 1)};
}

fragment float4 outputFragment(ScreenOutput in [[stage_in]],
                               texture2d<float, access::read> color [[texture(GPUColorTexture)]],
                               constant GPUFrame &frame [[buffer(GPUFrameBinding)]]) {
    float3 hdr = color.read(uint2(in.position.xy)).rgb * frame.parameters.x;
    float3 mapped = hdr / (1.0 + hdr);
    // The sRGB render target performs the linear-to-sRGB conversion.
    return float4(mapped, 1);
}

// MARK: - Debugger readback

// Each sample is preserved in its own plane, rather than silently resolving MSAA.
kernel void debugColorMS(texture2d_ms<float, access::read> source [[texture(0)]],
                         device float4 *output [[buffer(0)]], uint3 p [[thread_position_in_grid]]) {
    if (p.x < source.get_width() && p.y < source.get_height() && p.z < source.get_num_samples())
        output[(p.z * source.get_height() + p.y) * source.get_width() + p.x] = source.read(p.xy, p.z);
}

kernel void debugDepthMS(depth2d_ms<float, access::read> source [[texture(0)]],
                         device float4 *output [[buffer(0)]], uint3 p [[thread_position_in_grid]]) {
    if (p.x < source.get_width() && p.y < source.get_height() && p.z < source.get_num_samples()) {
        float depth = source.read(p.xy, p.z);
        output[(p.z * source.get_height() + p.y) * source.get_width() + p.x] = float4(depth, depth, depth, 1);
    }
}
