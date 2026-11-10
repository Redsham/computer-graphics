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
