import EngineCore
import Foundation
import simd

// MARK: - Captured resource data

public enum DebugPixelLayout: String, Codable, Sendable {
    case rgba16Float, rgba32Float, bgra8, rgba8, r32Float, r16Float, r8

    var bytesPerPixel: Int {
        switch self {
        case .rgba16Float:
            8
        case .rgba32Float:
            16
        case .bgra8, .rgba8, .r32Float:
            4
        case .r16Float:
            2
        case .r8:
            1
        }
    }
}

public struct CapturedTexture: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let width: Int
    public let height: Int
    public let samples: Int
    public let format: String
    public let isDepth: Bool
    public let isSRGB: Bool
    public let layout: DebugPixelLayout?
    public let bytesPerRow: Int
    public let bytesPerImage: Int
    public let bytes: Data
    public let note: String?

    public func pixel(x: Int, y: Int, sample: Int = 0) -> SIMD4<Float>? {
        guard let layout, (0..<width).contains(x), (0..<height).contains(y),
            (0..<samples).contains(sample)
        else {
            return nil
        }

        let offset = sample * bytesPerImage + y * bytesPerRow + x * layout.bytesPerPixel

        guard offset + layout.bytesPerPixel <= bytes.count else {
            return nil
        }

        func f32(_ index: Int) -> Float {
            bytes.withUnsafeBytes {
                Float(
                    bitPattern: UInt32(
                        littleEndian: $0.loadUnaligned(fromByteOffset: offset + index * 4, as: UInt32.self)))
            }
        }

        func f16(_ index: Int) -> Float {
            bytes.withUnsafeBytes { raw in
                BinaryScalar.float16(
                    UInt16(
                        littleEndian: raw.loadUnaligned(fromByteOffset: offset + index * 2, as: UInt16.self)))
            }
        }

        switch layout {
        case .rgba32Float:
            return SIMD4(f32(0), f32(1), f32(2), f32(3))
        case .rgba16Float:
            return SIMD4(f16(0), f16(1), f16(2), f16(3))
        case .bgra8:
            return SIMD4(
                Float(bytes[offset + 2]) / 255, Float(bytes[offset + 1]) / 255, Float(bytes[offset]) / 255,
                Float(bytes[offset + 3]) / 255)
        case .rgba8:
            return SIMD4(
                Float(bytes[offset]) / 255, Float(bytes[offset + 1]) / 255, Float(bytes[offset + 2]) / 255,
                Float(bytes[offset + 3]) / 255)
        case .r32Float:
            return SIMD4(repeating: f32(0))
        case .r16Float:
            return SIMD4(repeating: f16(0))
        case .r8:
            return SIMD4(repeating: Float(bytes[offset]) / 255)
        }
    }
}

public struct CapturedBuffer: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let length: Int
    public let sourceOffset: Int
    public let allocationLength: Int
    public let stride: Int?
    public let schema: String?
    public let bytes: Data
    public let note: String?
}

// MARK: - Captured frame data

public struct CapturedPass: Identifiable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let inputs: [String]
    public let outputs: [String]
    public let cpuMilliseconds: Double
    public let textures: [CapturedTexture]
    public let buffers: [CapturedBuffer]
}

public struct FrameCapture: Identifiable, Codable, Sendable {
    public let id: UInt64
    public let date: Date
    public let width: Int
    public let height: Int
    public let sampleCount: Int
    public let passes: [CapturedPass]
    public let bytesStored: Int
    public let notes: [String]

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
