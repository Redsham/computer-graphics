import simd

// MARK: - Resource identifiers

public struct MeshID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ value: UInt64) {
        rawValue = value
    }
}

public struct MaterialID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ value: UInt64) {
        rawValue = value
    }
}
