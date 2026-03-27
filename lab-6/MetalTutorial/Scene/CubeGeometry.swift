//
//  Geometry.swift
//  
//  Defines geometry types and cube mesh data for use in Renderer.swift.
//  Includes a Vertex struct with position, normal, and uv attributes matching Metal layout,
//  and a unit cube mesh with correct normals and UVs.
//

import simd
import Metal

public struct Vertex {
    public var position: simd_float3
    public var normal: simd_float3
    public var uv: simd_float2

    public init(position: simd_float3, normal: simd_float3, uv: simd_float2) {
        self.position = position
        self.normal = normal
        self.uv = uv
    }
}

public let cubeVertices: [Vertex] = [
    // Front face (+Z)
    Vertex(position: simd_float3(-0.5, -0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(0, 0)),
    Vertex(position: simd_float3( 0.5, -0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(1, 0)),
    Vertex(position: simd_float3( 0.5,  0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(1, 1)),
    Vertex(position: simd_float3(-0.5,  0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(0, 1)),

    // Back face (-Z)
    Vertex(position: simd_float3( 0.5, -0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(0, 0)),
    Vertex(position: simd_float3(-0.5, -0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(1, 0)),
    Vertex(position: simd_float3(-0.5,  0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(1, 1)),
    Vertex(position: simd_float3( 0.5,  0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(0, 1)),

    // Left face (-X)
    Vertex(position: simd_float3(-0.5, -0.5, -0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(0, 0)),
    Vertex(position: simd_float3(-0.5, -0.5,  0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(1, 0)),
    Vertex(position: simd_float3(-0.5,  0.5,  0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(1, 1)),
    Vertex(position: simd_float3(-0.5,  0.5, -0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(0, 1)),

    // Right face (+X)
    Vertex(position: simd_float3( 0.5, -0.5,  0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(0, 0)),
    Vertex(position: simd_float3( 0.5, -0.5, -0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(1, 0)),
    Vertex(position: simd_float3( 0.5,  0.5, -0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(1, 1)),
    Vertex(position: simd_float3( 0.5,  0.5,  0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(0, 1)),

    // Top face (+Y)
    Vertex(position: simd_float3(-0.5,  0.5,  0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(0, 0)),
    Vertex(position: simd_float3( 0.5,  0.5,  0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(1, 0)),
    Vertex(position: simd_float3( 0.5,  0.5, -0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(1, 1)),
    Vertex(position: simd_float3(-0.5,  0.5, -0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(0, 1)),

    // Bottom face (-Y)
    Vertex(position: simd_float3(-0.5, -0.5, -0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(0, 0)),
    Vertex(position: simd_float3( 0.5, -0.5, -0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(1, 0)),
    Vertex(position: simd_float3( 0.5, -0.5,  0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(1, 1)),
    Vertex(position: simd_float3(-0.5, -0.5,  0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(0, 1)),
]

public let cubeIndices: [UInt16] = [
    // Front face
    0, 1, 2,
    2, 3, 0,

    // Back face
    4, 5, 6,
    6, 7, 4,

    // Left face
    8, 9, 10,
    10, 11, 8,

    // Right face
    12, 13, 14,
    14, 15, 12,

    // Top face
    16, 17, 18,
    18, 19, 16,

    // Bottom face
    20, 21, 22,
    22, 23, 20,
]
