import EngineCore
import simd

extension ResourceStore {
    // MARK: - Procedural geometry

    public func makeCube() throws -> MeshID {
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            (SIMD3(0, 0, 1), [SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)]),
            (SIMD3(0, 0, -1), [SIMD3(1, -1, -1), SIMD3(-1, -1, -1), SIMD3(-1, 1, -1), SIMD3(1, 1, -1)]),
            (SIMD3(1, 0, 0), [SIMD3(1, -1, 1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(1, 1, 1)]),
            (SIMD3(-1, 0, 0), [SIMD3(-1, -1, -1), SIMD3(-1, -1, 1), SIMD3(-1, 1, 1), SIMD3(-1, 1, -1)]),
            (SIMD3(0, 1, 0), [SIMD3(-1, 1, 1), SIMD3(1, 1, 1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1)]),
            (SIMD3(0, -1, 0), [SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, -1, 1), SIMD3(-1, -1, 1)]),
        ]
        let vertices = faces.flatMap { normal, corners in
            [0, 1, 2, 0, 2, 3].map { MeshVertex(position: corners[$0] * 0.75, normal: normal) }
        }
        return try makeMesh(vertices: vertices)
    }
}
