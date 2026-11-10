import AppKit
import EngineCore
import EngineMetal
import SwiftUI

// MARK: - Frame and pass selection

@MainActor struct FrameDebuggerPanel: View {
    @ObservedObject var session: EngineSession

    @ObservedObject var state: FrameDebuggerViewState

    var body: some View {
        if let capture = session.capturedFrame {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame \(capture.id)")
                        .font(.headline)

                    Text(
                        "\(capture.width)×\(capture.height) · MSAA \(capture.sampleCount)×\n\(capture.bytesStored / 1024) KiB captured"
                    )
                    .font(.caption.monospaced())

                    List(selection: $state.passID) {
                        ForEach(capture.passes) { pass in
                            VStack(alignment: .leading) {
                                Text("\(pass.id + 1). \(pass.name)")

                                Text(String(format: "CPU encode %.3f ms", pass.cpuMilliseconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(pass.id)
                        }
                    }

                    Button("Export frame…") {
                        session.exportCapture()
                    }

                    Button("Discard capture") {
                        session.capturedFrame = nil
                        session.renderer.clearCapture()
                    }
                }
                .padding(10)
                .frame(width: 190)

                Divider()

                if let pass = capture.passes.first(where: {
                    $0.id == state.passID
                }) ?? capture.passes.first {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(
                                "Read: \(pass.inputs.joined(separator: ", ")) → Write: \(pass.outputs.joined(separator: ", "))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Spacer()

                            Picker(
                                "Resource",
                                selection: Binding(
                                    get: {
                                        selectedID(pass)
                                    },
                                    set: {
                                        state.resourceID = $0
                                    })
                            ) {
                                ForEach(pass.textures) {
                                    Text("Texture · \($0.name)")
                                        .tag($0.id)
                                }

                                ForEach(pass.buffers) {
                                    Text("Buffer · \($0.name)")
                                        .tag($0.id)
                                }
                            }
                            .frame(maxWidth: 340)
                        }
                        let selected = selectedID(pass)

                        if let texture = pass.textures.first(where: {
                            $0.id == selected
                        }) {
                            TextureInspector(
                                texture: texture,
                                export: {
                                    session.exportTexture(texture)
                                }, state: state.texture(texture.id)
                            )
                            .id(
                                texture.id)
                        } else if let buffer = pass.buffers.first(where: {
                            $0.id == selected
                        }) {
                            BufferInspector(
                                buffer: buffer,
                                export: {
                                    session.exportBuffer(buffer)
                                }, state: state.buffer(buffer.id)
                            )
                            .id(
                                buffer.id)
                        }
                    }
                    .padding(10)
                }
            }
            .onAppear { state.accept(captureID: capture.id) }
            .onChange(of: capture.id) { state.accept(captureID: capture.id) }
        } else {
            ContentUnavailableView {
                Label("No captured frame", systemImage: "camera.viewfinder")
            } description: {
                Text(
                    "Capture frame freezes the next frame and preserves textures and buffers after every pass. Use Xcode GPU trace for per-draw and shader inspection."
                )
            } actions: {
                Button("Capture frame") {
                    session.captureFrame()
                }
            }
        }
    }

    private func selectedID(_ pass: CapturedPass) -> String {
        if pass.textures.contains(where: {
            $0.id == state.resourceID
        })
            || pass.buffers.contains(where: {
                $0.id == state.resourceID
            })
        {
            return state.resourceID
        }

        return pass.textures.first?.id ?? pass.buffers.first?.id ?? ""
    }
}

// MARK: - Texture inspector

@MainActor private struct TextureInspector: View {
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

// MARK: - Texture preview generation

private struct PreviewRaster: Sendable {
    let width: Int
    let height: Int
    let data: Data
}

private func previewRGBA(
    _ texture: CapturedTexture, sample: Int, channel: String, autoRange: Bool, exposure: Double
) -> PreviewRaster? {
    guard !texture.bytes.isEmpty else {
        return nil
    }

    let width = min(512, texture.width)
    let height = max(1, texture.height * width / max(1, texture.width))
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
            let indices =
                channel == "RGB" ? [0, 1, 2] : [["R": 0, "G": 1, "B": 2, "A": 3][channel] ?? 0]

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
                let c = channel == "RGB" ? component : (["R": 0, "G": 1, "B": 2, "A": 3][channel] ?? 0)
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

// MARK: - Buffer inspector

@MainActor private struct BufferInspector: View {
    let buffer: CapturedBuffer
    let export: () -> Void

    @ObservedObject var state: BufferViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(
                    "\(buffer.name) · \(buffer.length) bytes · stride \(buffer.stride.map(String.init) ?? "raw")"
                )
                .font(.caption.monospaced())

                Spacer()

                Picker("Decode", selection: $state.interpretation) {
                    ForEach(["Float32", "UInt32", "Float16", "UInt8"], id: \.self) {
                        Text($0)
                            .tag($0)
                    }
                }
                .frame(width: 170)

                Stepper(
                    "Page \(state.page + 1)/\(max(1,(buffer.bytes.count + 255)/256))", value: $state.page,
                    in: 0...max(0, (buffer.bytes.count - 1) / 256)
                )
                .frame(width: 180)

                Button("Export binary…", action: export)
                    .disabled(buffer.bytes.isEmpty)
            }

            if let schema = buffer.schema {
                Text(schema)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let note = buffer.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(
                        Array(
                            stride(
                                from: state.page * 256, to: min(buffer.bytes.count, state.page * 256 + 256),
                                by: 16)),
                        id: \.self
                    ) { offset in
                        let end = min(buffer.bytes.count, offset + 16)
                        let hex = buffer.bytes[offset..<end].map {
                            String(format: "%02X", $0)
                        }.joined(
                            separator: " ")
                        Text(
                            String(format: "%08X  ", buffer.sourceOffset + offset)
                                + hex.padding(toLength: 48, withPad: " ", startingAt: 0) + "  "
                                + decode(offset: offset, end: end)
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func decode(offset: Int, end: Int) -> String {
        let size = state.interpretation == "UInt8" ? 1 : (state.interpretation == "Float16" ? 2 : 4)
        return stride(from: offset, through: end - size, by: size).map { position -> String in
            switch state.interpretation {
            case "UInt8":
                return "\(buffer.bytes[position])"
            case "Float16":
                return buffer.bytes.withUnsafeBytes { raw in
                    String(
                        format: "%.5g",
                        BinaryScalar.float16(
                            UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: position, as: UInt16.self))
                        ))
                }
            case "UInt32":
                return buffer.bytes.withUnsafeBytes {
                    "\(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: position, as: UInt32.self)))"
                }
            default:
                return buffer.bytes.withUnsafeBytes { raw in
                    let bits = UInt32(
                        littleEndian: raw.loadUnaligned(fromByteOffset: position, as: UInt32.self))
                    return String(format: "%.5g", Float(bitPattern: bits))
                }
            }
        }.joined(separator: "  ")
    }
}
