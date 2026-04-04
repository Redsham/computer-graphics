import Metal
import MetalKit
import simd

struct Vertex {
    var position: simd_float3
    var normal: simd_float3
    var uv: simd_float2
}

struct TerrainControlPoint {
    var position: simd_float3
    var uv: simd_float2
}

struct TerrainPatchGeometry {
    let controlPointBuffer: MTLBuffer
    let patchInfoBuffer: MTLBuffer
    let tessellationFactorBuffer: MTLBuffer
    let patchCount: Int
    let boundsMin: simd_float2
    let boundsMax: simd_float2
}

enum GeometryPrimitives {
    static func makeCubeDrawCall(device: MTLDevice) -> GeometryDrawCall {
        let vertexBuffer = device.makeBuffer(
            bytes: cubeVertices,
            length: cubeVertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )!

        let indexBuffer = device.makeBuffer(
            bytes: cubeIndices,
            length: cubeIndices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        )!

        let loader = MTKTextureLoader(device: device)
        let albedoTexture: MTLTexture?
        if let url = Bundle.main.url(forResource: "planks", withExtension: "png") {
            albedoTexture = try? loader.newTexture(URL: url, options: [MTKTextureLoader.Option.SRGB: false])
        } else {
            albedoTexture = nil
        }

        return .indexed(IndexedGeometryDrawCall(
            vertexBuffer: vertexBuffer,
            vertexBufferOffset: 0,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            indexCount: cubeIndices.count,
            indexType: .uint16,
            primitiveType: .triangle,
            modelMatrix: matrix_identity_float4x4,
            material: MaterialDrawState(
                albedoTexture: albedoTexture,
                normalTexture: nil,
                displacementTexture: nil,
                specularStrength: 0.45,
                roughness: 0.35,
                opacity: 1.0
            )
        ))
    }

    static func makeTerrainPatch(device: MTLDevice,
                                 size: simd_float2 = simd_float2(repeating: 420.0),
                                 center: simd_float2 = simd_float2(0.0, -220.0),
                                 patchResolution: Int = 8,
                                 minFactor: Float = 2.0,
                                 maxFactor: Float = 24.0,
                                 minDistance: Float = 150.0,
                                 maxDistance: Float = 1500.0) -> TerrainPatchGeometry {
        let resolution = max(1, patchResolution)
        let halfSize = size * 0.5
        let patchSize = size / Float(resolution)
        var controlPoints: [TerrainControlPoint] = []
        controlPoints.reserveCapacity(resolution * resolution * 4)

        var patchInfos: [TessellationPatchInfo] = []
        patchInfos.reserveCapacity(resolution * resolution)

        for z in 0 ..< resolution {
            for x in 0 ..< resolution {
                let x0 = center.x - halfSize.x + Float(x) * patchSize.x
                let x1 = x0 + patchSize.x
                let z0 = center.y - halfSize.y + Float(z) * patchSize.y
                let z1 = z0 + patchSize.y

                let u0 = Float(x) / Float(resolution)
                let u1 = Float(x + 1) / Float(resolution)
                let v0 = Float(z) / Float(resolution)
                let v1 = Float(z + 1) / Float(resolution)

                controlPoints.append(TerrainControlPoint(position: simd_float3(x0, 0.0, z0), uv: simd_float2(u0, v0)))
                controlPoints.append(TerrainControlPoint(position: simd_float3(x1, 0.0, z0), uv: simd_float2(u1, v0)))
                controlPoints.append(TerrainControlPoint(position: simd_float3(x0, 0.0, z1), uv: simd_float2(u0, v1)))
                controlPoints.append(TerrainControlPoint(position: simd_float3(x1, 0.0, z1), uv: simd_float2(u1, v1)))

                patchInfos.append(
                    TessellationPatchInfo(
                        patchMin: simd_float2(x0, z0),
                        patchMax: simd_float2(x1, z1)
                    )
                )
            }
        }

        let factorBufferLength = MemoryLayout<UInt16>.stride * 6 * patchInfos.count
        return TerrainPatchGeometry(
            controlPointBuffer: device.makeBuffer(
                bytes: controlPoints,
                length: MemoryLayout<TerrainControlPoint>.stride * controlPoints.count
            )!,
            patchInfoBuffer: device.makeBuffer(
                bytes: patchInfos,
                length: MemoryLayout<TessellationPatchInfo>.stride * patchInfos.count
            )!,
            tessellationFactorBuffer: device.makeBuffer(length: factorBufferLength)!,
            patchCount: patchInfos.count,
            boundsMin: simd_float2(center.x - halfSize.x, center.y - halfSize.y),
            boundsMax: simd_float2(center.x + halfSize.x, center.y + halfSize.y)
        )
    }

    private static let cubeVertices: [Vertex] = [
        Vertex(position: simd_float3(-0.5, -0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(0, 0)),
        Vertex(position: simd_float3( 0.5, -0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(1, 0)),
        Vertex(position: simd_float3( 0.5,  0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(1, 1)),
        Vertex(position: simd_float3(-0.5,  0.5,  0.5), normal: simd_float3(0, 0, 1), uv: simd_float2(0, 1)),

        Vertex(position: simd_float3( 0.5, -0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(0, 0)),
        Vertex(position: simd_float3(-0.5, -0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(1, 0)),
        Vertex(position: simd_float3(-0.5,  0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(1, 1)),
        Vertex(position: simd_float3( 0.5,  0.5, -0.5), normal: simd_float3(0, 0, -1), uv: simd_float2(0, 1)),

        Vertex(position: simd_float3(-0.5, -0.5, -0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(0, 0)),
        Vertex(position: simd_float3(-0.5, -0.5,  0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(1, 0)),
        Vertex(position: simd_float3(-0.5,  0.5,  0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(1, 1)),
        Vertex(position: simd_float3(-0.5,  0.5, -0.5), normal: simd_float3(-1, 0, 0), uv: simd_float2(0, 1)),

        Vertex(position: simd_float3( 0.5, -0.5,  0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(0, 0)),
        Vertex(position: simd_float3( 0.5, -0.5, -0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(1, 0)),
        Vertex(position: simd_float3( 0.5,  0.5, -0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(1, 1)),
        Vertex(position: simd_float3( 0.5,  0.5,  0.5), normal: simd_float3(1, 0, 0), uv: simd_float2(0, 1)),

        Vertex(position: simd_float3(-0.5,  0.5,  0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(0, 0)),
        Vertex(position: simd_float3( 0.5,  0.5,  0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(1, 0)),
        Vertex(position: simd_float3( 0.5,  0.5, -0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(1, 1)),
        Vertex(position: simd_float3(-0.5,  0.5, -0.5), normal: simd_float3(0, 1, 0), uv: simd_float2(0, 1)),

        Vertex(position: simd_float3(-0.5, -0.5, -0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(0, 0)),
        Vertex(position: simd_float3( 0.5, -0.5, -0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(1, 0)),
        Vertex(position: simd_float3( 0.5, -0.5,  0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(1, 1)),
        Vertex(position: simd_float3(-0.5, -0.5,  0.5), normal: simd_float3(0, -1, 0), uv: simd_float2(0, 1))
    ]

    private static let cubeIndices: [UInt16] = [
        0, 1, 2, 2, 3, 0,
        4, 5, 6, 6, 7, 4,
        8, 9, 10, 10, 11, 8,
        12, 13, 14, 14, 15, 12,
        16, 17, 18, 18, 19, 16,
        20, 21, 22, 22, 23, 20
    ]
}
