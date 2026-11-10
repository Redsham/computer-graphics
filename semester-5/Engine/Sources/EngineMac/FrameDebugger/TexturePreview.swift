import Foundation
import EngineMetal

// MARK: - Texture preview generation

struct PreviewRaster: Sendable {
    let width: Int
    let height: Int
    let data: Data
}

func previewRGBA(
    _ texture: CapturedTexture, sample: Int, channel: String, autoRange: Bool, exposure: Double
) -> PreviewRaster? {
    guard !texture.bytes.isEmpty else {
        return nil
    }

    let width = min(512, texture.width)
    let height = max(1, texture.height * width / max(1, texture.width))
    let selectedChannel = ["R": 0, "G": 1, "B": 2, "A": 3][channel] ?? 0
    let indices = channel == "RGB" ? [0, 1, 2] : [selectedChannel]
    var values: [SIMD4<Float>] = []
    values.reserveCapacity(width * height)
    var minimum = Float.infinity
    var maximum = -Float.infinity

    for y in 0..<height {
        if Task.isCancelled {
            return nil
        }

        for x in 0..<width {
            let pixel =
                texture.pixel(x: x * texture.width / width, y: y * texture.height / height, sample: sample)
                ?? .zero
            values.append(pixel)

            for index in indices where pixel[index].isFinite {
                minimum = min(minimum, pixel[index])
                maximum = max(maximum, pixel[index])
            }
        }
    }

    var data = Data(count: width * height * 4)
    data.withUnsafeMutableBytes { raw in
        let destination = raw.bindMemory(to: UInt8.self)

        for (index, pixel) in values.enumerated() {
            for component in 0..<3 {
                let c = channel == "RGB" ? component : selectedChannel
                var value = pixel[c]

                if !value.isFinite {
                    value = 0
                }

                if autoRange {
                    value = (value - minimum) / max(0.000001, maximum - minimum)
                } else if !texture.isDepth && !texture.isSRGB && channel != "A" {
                    value = max(0, value * Float(exposure))
                    value = value / (1 + value)
                    value = value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
                }

                destination[index * 4 + component] = UInt8(min(max(value, 0), 1) * 255)
            }

            destination[index * 4 + 3] = 255
        }
    }
    return PreviewRaster(width: width, height: height, data: data)
}
