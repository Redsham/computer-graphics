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
    static func makeSolidColorTexture(device: MTLDevice, color: simd_float4) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        let texture = device.makeTexture(descriptor: descriptor)!
        let bytes = [
            UInt8(max(0, min(255, Int(color.x * 255.0)))),
            UInt8(max(0, min(255, Int(color.y * 255.0)))),
            UInt8(max(0, min(255, Int(color.z * 255.0)))),
            UInt8(max(0, min(255, Int(color.w * 255.0))))
        ]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: 4
        )
        return texture
    }

    static func makeColoredCubeDrawCall(device: MTLDevice, color: simd_float4) -> GeometryDrawCall {
        var drawCall = makeCubeDrawCall(device: device)
        guard case var .indexed(indexedDrawCall) = drawCall else { return drawCall }
        indexedDrawCall.material = MaterialDrawState(
            albedoTexture: makeSolidColorTexture(device: device, color: color),
            normalTexture: nil,
            displacementTexture: nil,
            specularStrength: 0.22,
            roughness: 0.55,
            opacity: 1.0
        )
        drawCall = .indexed(indexedDrawCall)
        return drawCall
    }

    static func makeCylinderDrawCall(device: MTLDevice,
                                     radius: Float,
                                     height: Float,
                                     segments: Int = 40,
                                     color: simd_float4) -> GeometryDrawCall {
        let segmentCount = max(8, min(segments, 96))
        let halfHeight = height * 0.5
        var vertices: [Vertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity(segmentCount * 4 + 2)
        indices.reserveCapacity(segmentCount * 12)

        for i in 0 ... segmentCount {
            let angle = Float(i) / Float(segmentCount) * .pi * 2.0
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let normal = simd_normalize(simd_float3(x, 0.0, z))
            let u = Float(i) / Float(segmentCount)
            vertices.append(Vertex(position: simd_float3(x, -halfHeight, z), normal: normal, uv: simd_float2(u, 1.0)))
            vertices.append(Vertex(position: simd_float3(x, halfHeight, z), normal: normal, uv: simd_float2(u, 0.0)))
        }

        for i in 0 ..< segmentCount {
            let base = UInt16(i * 2)
            indices.append(contentsOf: [base, base + 1, base + 2, base + 1, base + 3, base + 2])
        }

        let bottomCenter = UInt16(vertices.count)
        vertices.append(Vertex(position: simd_float3(0.0, -halfHeight, 0.0), normal: simd_float3(0.0, -1.0, 0.0), uv: simd_float2(0.5, 0.5)))
        let topCenter = UInt16(vertices.count)
        vertices.append(Vertex(position: simd_float3(0.0, halfHeight, 0.0), normal: simd_float3(0.0, 1.0, 0.0), uv: simd_float2(0.5, 0.5)))

        for i in 0 ..< segmentCount {
            let a = UInt16(i * 2)
            let b = UInt16(((i + 1) % segmentCount) * 2)
            indices.append(contentsOf: [bottomCenter, b, a])
            indices.append(contentsOf: [topCenter, a + 1, b + 1])
        }

        return makeIndexedDrawCall(
            device: device,
            vertices: vertices,
            indices: indices,
            color: color,
            specularStrength: 0.32,
            roughness: 0.38
        )
    }

    static func makeConeDrawCall(device: MTLDevice,
                                 radius: Float,
                                 height: Float,
                                 segments: Int = 40,
                                 color: simd_float4) -> GeometryDrawCall {
        let segmentCount = max(8, min(segments, 96))
        let halfHeight = height * 0.5
        var vertices: [Vertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity(segmentCount * 2 + 2)
        indices.reserveCapacity(segmentCount * 6)

        let slope = radius / max(height, 0.0001)
        for i in 0 ..< segmentCount {
            let angle = Float(i) / Float(segmentCount) * .pi * 2.0
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let normal = simd_normalize(simd_float3(cos(angle), slope, sin(angle)))
            vertices.append(Vertex(position: simd_float3(x, -halfHeight, z), normal: normal, uv: simd_float2(Float(i) / Float(segmentCount), 1.0)))
        }

        let apex = UInt16(vertices.count)
        vertices.append(Vertex(position: simd_float3(0.0, halfHeight, 0.0), normal: simd_float3(0.0, 1.0, 0.0), uv: simd_float2(0.5, 0.0)))
        let bottomCenter = UInt16(vertices.count)
        vertices.append(Vertex(position: simd_float3(0.0, -halfHeight, 0.0), normal: simd_float3(0.0, -1.0, 0.0), uv: simd_float2(0.5, 0.5)))

        for i in 0 ..< segmentCount {
            let a = UInt16(i)
            let b = UInt16((i + 1) % segmentCount)
            indices.append(contentsOf: [a, apex, b])
            indices.append(contentsOf: [bottomCenter, b, a])
        }

        return makeIndexedDrawCall(
            device: device,
            vertices: vertices,
            indices: indices,
            color: color,
            specularStrength: 0.24,
            roughness: 0.42
        )
    }

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

    private static func makeIndexedDrawCall(device: MTLDevice,
                                            vertices: [Vertex],
                                            indices: [UInt16],
                                            color: simd_float4,
                                            specularStrength: Float,
                                            roughness: Float) -> GeometryDrawCall {
        let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )!

        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        )!

        return .indexed(IndexedGeometryDrawCall(
            vertexBuffer: vertexBuffer,
            vertexBufferOffset: 0,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            indexCount: indices.count,
            indexType: .uint16,
            primitiveType: .triangle,
            modelMatrix: matrix_identity_float4x4,
            material: MaterialDrawState(
                albedoTexture: makeSolidColorTexture(device: device, color: color),
                normalTexture: nil,
                displacementTexture: nil,
                specularStrength: specularStrength,
                roughness: roughness,
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
