import AppKit
import EngineMetal
import SwiftUI

// MARK: - Texture inspector

@MainActor struct TextureInspector: View {
    let texture: CapturedTexture
    let export: () -> Void
    @State private var image: NSImage?
    @State private var rendering = false

    private var taskID: String {
        "\(texture.id).\(state.sample).\(state.channel).\(state.autoRange).\(state.exposure)"
    }

    private var previewWidth: Int {
        min(512, texture.width)
    }

    private var previewHeight: Int {
        max(1, texture.height * previewWidth / max(1, texture.width))
    }

    private var previewScale: CGFloat {
        min(1, 150 / CGFloat(previewHeight))
    }

    @ObservedObject var state: TextureViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(
                    "\(texture.name) · \(texture.format) · \(texture.width)×\(texture.height) · \(texture.samples) samples"
                )
                .font(.caption.monospaced())
                .textSelection(.enabled)

                Spacer()

                Button("Raw bytes…", action: export)
                    .disabled(texture.bytes.isEmpty)
            }

            if let note = texture.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Picker("Channel", selection: $state.channel) {
                    ForEach(["RGB", "R", "G", "B", "A"], id: \.self) {
                        Text($0)
                            .tag($0)
                    }
                }
                .frame(width: 125)

                if texture.samples > 1 {
                    Picker("Sample", selection: $state.sample) {
                        ForEach(0..<texture.samples, id: \.self) {
                            Text("\($0)")
                                .tag($0)
                        }
                    }
                    .frame(width: 110)
                }

                Toggle("Auto range", isOn: $state.autoRange)

                Picker("Zoom", selection: $state.zoom) {
                    Text("1×")
                        .tag(CGFloat(1))

                    Text("2×")
                        .tag(CGFloat(2))

                    Text("4×")
                        .tag(CGFloat(4))
                }
                .frame(width: 100)

                Text("Exposure")
                    .font(.caption)

                Slider(value: $state.exposure, in: 0.1...8)
                    .frame(width: 90)

                if rendering {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(alignment: .top) {
                ScrollView([.horizontal, .vertical]) {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .frame(
                                width: CGFloat(previewWidth) * previewScale * state.zoom,
                                height: CGFloat(previewHeight) * previewScale * state.zoom
                            )
                            .onContinuousHover { phase in
                                if case .active(let point) = phase {
                                    state.pixelX = min(
                                        texture.width - 1,
                                        max(
                                            0,
                                            Int(
                                                point.x / (CGFloat(previewWidth) * previewScale * state.zoom)
                                                    * CGFloat(texture.width))))
                                    state.pixelY = min(
                                        texture.height - 1,
                                        max(
                                            0,
                                            Int(
                                                point.y / (CGFloat(previewHeight) * previewScale * state.zoom)
                                                    * CGFloat(texture.height)))
                                    )
                                }
                            }
                    } else {
                        Text(texture.bytes.isEmpty ? "No pixel data stored." : "Preparing preview…")
                            .font(
                                .caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Pixel inspector")
                        .font(.headline)

                    HStack {
                        Text("X")

                        TextField("X", value: $state.pixelX, format: .number)
                            .frame(width: 50)

                        Text("Y")

                        TextField("Y", value: $state.pixelY, format: .number)
                            .frame(width: 50)
                    }
                    .textFieldStyle(.roundedBorder)

                    if let value = texture.pixel(x: state.pixelX, y: state.pixelY, sample: state.sample) {
                        ForEach(0..<4) { index in
                            Text(String(format: "%@  %.7g", ["R", "G", "B", "A"][index], value[index]))
                                .font(
                                    .caption.monospaced()
                                )
                                .textSelection(.enabled)
                        }
                    }

                    Text(
                        texture.isDepth
                            ? "Raw device depth 0…1. Auto range increases contrast."
                            : "Values are captured data. Preview tone maps linear RGB; sRGB bytes remain encoded."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(width: 220)
            }
        }
        .task(id: taskID) {
            guard !texture.bytes.isEmpty else {
                image = nil
                return
            }

            rendering = true
            let captured = texture
            let chosenSample = state.sample
            let chosenChannel = state.channel
            let range = state.autoRange
            let gain = state.exposure
            let task = Task.detached(priority: .userInitiated) {
                previewRGBA(
                    captured, sample: chosenSample, channel: chosenChannel, autoRange: range, exposure: gain)
            }
            let raster = await withTaskCancellationHandler(
                operation: {
                    await task.value
                },
                onCancel: {
                    task.cancel()
                })

            guard !Task.isCancelled else {
                return
            }

            if let raster,
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: raster.width, pixelsHigh: raster.height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: raster.width * 4, bitsPerPixel: 32),
                let pointer = bitmap.bitmapData
            {
                raster.data.copyBytes(to: pointer, count: raster.data.count)
                let next = NSImage(size: NSSize(width: raster.width, height: raster.height))
                next.addRepresentation(bitmap)
                image = next
            }

            rendering = false
        }
    }
}
