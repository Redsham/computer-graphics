import simd

struct AABB {
    var min: simd_float3
    var max: simd_float3

    static var empty: AABB {
        AABB(
            min: simd_float3(repeating: Float.greatestFiniteMagnitude),
            max: simd_float3(repeating: -Float.greatestFiniteMagnitude)
        )
    }

    var isValid: Bool {
        min.x <= max.x && min.y <= max.y && min.z <= max.z
    }

    var center: simd_float3 {
        (min + max) * 0.5
    }

    var extent: simd_float3 {
        max - min
    }

    var corners: [simd_float3] {
        [
            simd_float3(min.x, min.y, min.z),
            simd_float3(max.x, min.y, min.z),
            simd_float3(max.x, max.y, min.z),
            simd_float3(min.x, max.y, min.z),
            simd_float3(min.x, min.y, max.z),
            simd_float3(max.x, min.y, max.z),
            simd_float3(max.x, max.y, max.z),
            simd_float3(min.x, max.y, max.z)
        ]
    }

    func union(_ other: AABB) -> AABB {
        guard isValid else { return other }
        guard other.isValid else { return self }
        return AABB(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }

    mutating func include(_ other: AABB) {
        self = union(other)
    }

    func contains(_ other: AABB) -> Bool {
        guard isValid, other.isValid else { return false }
        let epsilon: Float = 0.0001
        return other.min.x >= min.x - epsilon &&
            other.min.y >= min.y - epsilon &&
            other.min.z >= min.z - epsilon &&
            other.max.x <= max.x + epsilon &&
            other.max.y <= max.y + epsilon &&
            other.max.z <= max.z + epsilon
    }

    func transformed(by matrix: simd_float4x4) -> AABB {
        var result = AABB.empty
        for corner in corners {
            let p = matrix * simd_float4(corner, 1.0)
            result.include(AABB(min: p.xyz, max: p.xyz))
        }
        return result
    }

    func paddedForOctree() -> AABB {
        let e = extent
        let maxExtent = Swift.max(Swift.max(e.x, e.y), e.z)
        let pad = Swift.max(maxExtent * 0.01, 1.0)
        return AABB(min: min - simd_float3(repeating: pad), max: max + simd_float3(repeating: pad))
    }
}

struct FrustumPlane {
    var normal: simd_float3
    var distance: Float

    init(coefficients: simd_float4) {
        let n = coefficients.xyz
        let length = max(simd_length(n), 0.000001)
        self.normal = n / length
        self.distance = coefficients.w / length
    }

    func signedDistance(to point: simd_float3) -> Float {
        simd_dot(normal, point) + distance
    }
}

struct ViewFrustum {
    enum Intersection {
        case outside
        case intersects
        case inside
    }

    var planes: [FrustumPlane]

    init(viewProjectionMatrix matrix: simd_float4x4) {
        let row0 = Self.row(matrix, 0)
        let row1 = Self.row(matrix, 1)
        let row2 = Self.row(matrix, 2)
        let row3 = Self.row(matrix, 3)

        planes = [
            FrustumPlane(coefficients: row3 + row0),
            FrustumPlane(coefficients: row3 - row0),
            FrustumPlane(coefficients: row3 + row1),
            FrustumPlane(coefficients: row3 - row1),
            FrustumPlane(coefficients: row2),
            FrustumPlane(coefficients: row3 - row2)
        ]
    }

    func intersects(_ bounds: AABB) -> Bool {
        classify(bounds) != .outside
    }

    func classify(_ bounds: AABB) -> Intersection {
        guard bounds.isValid else { return .outside }

        var isFullyInside = true
        for plane in planes {
            let positiveVertex = simd_float3(
                plane.normal.x >= 0 ? bounds.max.x : bounds.min.x,
                plane.normal.y >= 0 ? bounds.max.y : bounds.min.y,
                plane.normal.z >= 0 ? bounds.max.z : bounds.min.z
            )

            if plane.signedDistance(to: positiveVertex) < 0 {
                return .outside
            }

            let negativeVertex = simd_float3(
                plane.normal.x >= 0 ? bounds.min.x : bounds.max.x,
                plane.normal.y >= 0 ? bounds.min.y : bounds.max.y,
                plane.normal.z >= 0 ? bounds.min.z : bounds.max.z
            )

            if plane.signedDistance(to: negativeVertex) < 0 {
                isFullyInside = false
            }
        }

        return isFullyInside ? .inside : .intersects
    }

    static func worldCorners(viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4) -> [simd_float3] {
        let inverseViewProjection = (projectionMatrix * viewMatrix).inverse
        let ndcCorners: [simd_float3] = [
            simd_float3(-1, -1, 0),
            simd_float3(1, -1, 0),
            simd_float3(1, 1, 0),
            simd_float3(-1, 1, 0),
            simd_float3(-1, -1, 1),
            simd_float3(1, -1, 1),
            simd_float3(1, 1, 1),
            simd_float3(-1, 1, 1)
        ]

        return ndcCorners.map { corner in
            let world = inverseViewProjection * simd_float4(corner, 1.0)
            let w = abs(world.w) > 0.000001 ? world.w : 0.000001
            return world.xyz / w
        }
    }

    private static func row(_ matrix: simd_float4x4, _ index: Int) -> simd_float4 {
        simd_float4(matrix[0][index], matrix[1][index], matrix[2][index], matrix[3][index])
    }
}

struct CullingOptions {
    var frustumCullingEnabled: Bool
    var octreeCullingEnabled: Bool
    var collectDebugInfo: Bool
}

struct CullingObject {
    var id: Int
    var bounds: AABB
    var drawCalls: [GeometryDrawCall]
    var label: String
}

struct CullingDebugObject {
    var id: Int
    var bounds: AABB
    var isVisible: Bool
    var label: String
}

struct CullingStats {
    var totalObjects: Int
    var visibleObjects: Int
    var culledObjects: Int
    var visitedOctreeNodes: Int
}

struct SceneFrameData {
    var drawCalls: [GeometryDrawCall]
    var debugObjects: [CullingDebugObject]
    var octreeDebugBounds: [AABB]
    var sceneBounds: AABB
    var stats: CullingStats
}

enum SceneCullingEvaluator {
    static func makeFrameData(objects: [CullingObject],
                              octree: Octree,
                              sceneBounds: AABB,
                              viewMatrix: simd_float4x4,
                              projectionMatrix: simd_float4x4,
                              options: CullingOptions) -> SceneFrameData {
        let frustum = ViewFrustum(viewProjectionMatrix: projectionMatrix * viewMatrix)
        let useOctree = options.octreeCullingEnabled
        let useFrustum = options.frustumCullingEnabled || useOctree

        var visibleFlags = Array(repeating: false, count: objects.count)
        let octreeDebugBounds: [AABB]
        let visitedNodeCount: Int

        if useOctree {
            let query = octree.query(frustum: frustum, collectDebugBounds: options.collectDebugInfo)
            for index in query.indices {
                visibleFlags[index] = true
            }
            octreeDebugBounds = query.visitedNodeBounds
            visitedNodeCount = query.visitedNodeCount
        } else if useFrustum {
            for index in objects.indices {
                visibleFlags[index] = frustum.intersects(objects[index].bounds)
            }
            octreeDebugBounds = []
            visitedNodeCount = 0
        } else {
            visibleFlags = Array(repeating: true, count: objects.count)
            octreeDebugBounds = []
            visitedNodeCount = 0
        }

        #if DEBUG
        if useOctree && options.collectDebugInfo {
            let linearIndices = Set(objects.indices.filter { frustum.intersects(objects[$0].bounds) })
            let octreeIndices = Set(objects.indices.filter { visibleFlags[$0] })
            if linearIndices != octreeIndices {
                print("[Culling] Octree mismatch: linear=\(linearIndices.count), octree=\(octreeIndices.count)")
            }
        }
        #endif

        let orderedVisibleIndices = objects.indices.filter { visibleFlags[$0] }
        let drawCalls = orderedVisibleIndices.flatMap { objects[$0].drawCalls }
        let debugObjects = options.collectDebugInfo
            ? objects.indices.map { index in
                CullingDebugObject(
                    id: objects[index].id,
                    bounds: objects[index].bounds,
                    isVisible: visibleFlags[index],
                    label: objects[index].label
                )
            }
            : []
        let visibleObjectCount = orderedVisibleIndices.count

        return SceneFrameData(
            drawCalls: drawCalls,
            debugObjects: debugObjects,
            octreeDebugBounds: octreeDebugBounds,
            sceneBounds: sceneBounds,
            stats: CullingStats(
                totalObjects: objects.count,
                visibleObjects: visibleObjectCount,
                culledObjects: objects.count - visibleObjectCount,
                visitedOctreeNodes: visitedNodeCount
            )
        )
    }
}

struct OctreeQueryResult {
    var indices: [Int] = []
    var visitedNodeBounds: [AABB] = []
    var visitedNodeCount: Int = 0
}

final class Octree {
    private final class Node {
        let bounds: AABB
        var objectIndices: [Int] = []
        var children: [Node] = []

        init(bounds: AABB) {
            self.bounds = bounds
        }
    }

    private let objects: [CullingObject]
    private let maxDepth: Int
    private let maxObjectsPerLeaf: Int
    private let root: Node

    init(objects: [CullingObject], maxDepth: Int = 7, maxObjectsPerLeaf: Int = 24) {
        self.objects = objects
        self.maxDepth = maxDepth
        self.maxObjectsPerLeaf = maxObjectsPerLeaf

        let rootBounds = objects.reduce(AABB.empty) { partial, object in
            partial.union(object.bounds)
        }.paddedForOctree()
        self.root = Octree.buildNode(
            bounds: rootBounds,
            indices: Array(objects.indices),
            objects: objects,
            depth: 0,
            maxDepth: maxDepth,
            maxObjectsPerLeaf: maxObjectsPerLeaf
        )
    }

    func query(frustum: ViewFrustum, collectDebugBounds: Bool) -> OctreeQueryResult {
        var result = OctreeQueryResult()
        query(node: root, frustum: frustum, collectDebugBounds: collectDebugBounds, result: &result)
        return result
    }

    private func query(node: Node, frustum: ViewFrustum, collectDebugBounds: Bool, result: inout OctreeQueryResult) {
        result.visitedNodeCount += 1
        if collectDebugBounds {
            result.visitedNodeBounds.append(node.bounds)
        }

        switch frustum.classify(node.bounds) {
        case .outside:
            return
        case .inside:
            collectSubtreeObjectIndices(from: node, result: &result)
            return
        case .intersects:
            break
        }

        for index in node.objectIndices where frustum.intersects(objects[index].bounds) {
            result.indices.append(index)
        }

        for child in node.children {
            query(node: child, frustum: frustum, collectDebugBounds: collectDebugBounds, result: &result)
        }
    }

    private func collectSubtreeObjectIndices(from node: Node, result: inout OctreeQueryResult) {
        result.indices.append(contentsOf: node.objectIndices)
        for child in node.children {
            collectSubtreeObjectIndices(from: child, result: &result)
        }
    }

    private static func buildNode(bounds: AABB,
                                  indices: [Int],
                                  objects: [CullingObject],
                                  depth: Int,
                                  maxDepth: Int,
                                  maxObjectsPerLeaf: Int) -> Node {
        let node = Node(bounds: bounds)
        guard depth < maxDepth, indices.count > maxObjectsPerLeaf else {
            node.objectIndices = indices
            return node
        }

        let childBounds = makeOctants(for: bounds)
        var childBuckets = Array(repeating: [Int](), count: childBounds.count)
        var retainedIndices: [Int] = []
        retainedIndices.reserveCapacity(indices.count)

        for index in indices {
            let objectBounds = objects[index].bounds
            if let childIndex = childBounds.firstIndex(where: { $0.contains(objectBounds) }) {
                childBuckets[childIndex].append(index)
            } else {
                retainedIndices.append(index)
            }
        }

        if childBuckets.allSatisfy(\.isEmpty) {
            node.objectIndices = indices
            return node
        }

        node.objectIndices = retainedIndices
        node.children = childBuckets.enumerated().compactMap { offset, bucket in
            guard !bucket.isEmpty else { return nil }
            return buildNode(
                bounds: childBounds[offset],
                indices: bucket,
                objects: objects,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxObjectsPerLeaf: maxObjectsPerLeaf
            )
        }
        return node
    }

    private static func makeOctants(for bounds: AABB) -> [AABB] {
        let c = bounds.center
        return [
            AABB(min: simd_float3(bounds.min.x, bounds.min.y, bounds.min.z), max: simd_float3(c.x, c.y, c.z)),
            AABB(min: simd_float3(c.x, bounds.min.y, bounds.min.z), max: simd_float3(bounds.max.x, c.y, c.z)),
            AABB(min: simd_float3(bounds.min.x, c.y, bounds.min.z), max: simd_float3(c.x, bounds.max.y, c.z)),
            AABB(min: simd_float3(c.x, c.y, bounds.min.z), max: simd_float3(bounds.max.x, bounds.max.y, c.z)),
            AABB(min: simd_float3(bounds.min.x, bounds.min.y, c.z), max: simd_float3(c.x, c.y, bounds.max.z)),
            AABB(min: simd_float3(c.x, bounds.min.y, c.z), max: simd_float3(bounds.max.x, c.y, bounds.max.z)),
            AABB(min: simd_float3(bounds.min.x, c.y, c.z), max: simd_float3(c.x, bounds.max.y, bounds.max.z)),
            AABB(min: simd_float3(c.x, c.y, c.z), max: simd_float3(bounds.max.x, bounds.max.y, bounds.max.z))
        ]
    }
}

private extension simd_float4 {
    var xyz: simd_float3 {
        simd_float3(x, y, z)
    }
}
