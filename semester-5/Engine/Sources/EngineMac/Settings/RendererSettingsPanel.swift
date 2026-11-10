import EngineCore
import SwiftUI
import simd

@MainActor struct RendererSettingsPanel: View {
    @ObservedObject var session: EngineSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Renderer")
                    .font(.title2.bold())

                Text("Engine Sandbox")
                    .foregroundStyle(.secondary)

                Divider()

                Picker("Target FPS", selection: $session.configuration.targetFPS) {
                    ForEach(
                        Array(Set([30, 60, 120, 144, 240, session.configuration.targetFPS])).sorted(),
                        id: \.self
                    ) {
                        Text("\($0)")
                            .tag($0)
                    }
                }

                Picker("MSAA", selection: $session.configuration.sampleCount) {
                    Text("1×")
                        .tag(1)

                    Text("4×")
                        .tag(4)
                }
                .pickerStyle(.segmented)

                Toggle("Wireframe", isOn: $session.configuration.wireframe)

                ColorPicker("Background", selection: background, supportsOpacity: false)

                setting("Exposure", value: $session.configuration.exposure, range: 0.1...8)

                Divider()

                Text("Camera")
                    .font(.headline)

                setting("Field of view", value: $session.configuration.fieldOfView, range: 20...110)

                setting("Movement speed", value: $session.configuration.cameraSpeed, range: 0.1...20)

                Button("Restore defaults") {
                    session.resetSettings()
                }

                if let message = session.message {
                    Divider()
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)

                    if session.isRenderingPaused {
                        Button("Retry rendering") {
                            session.retry()
                        }
                    }

                    Button("Dismiss") {
                        session.clearMessage()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    // MARK: - Settings controls

    private var background: Binding<Color> {
        Binding(
            get: {
                let c = session.configuration.background
                return Color(.sRGBLinear, red: Double(c.x), green: Double(c.y), blue: Double(c.z))
            },
            set: { color in
                guard let cgSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
                    let space = NSColorSpace(cgColorSpace: cgSpace),
                    let rgb = NSColor(color).usingColorSpace(space)
                else {
                    return
                }

                session.configuration.background = simd_clamp(
                    SIMD3(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent)),
                    .zero, .one)
            })
    }

    private func setting(_ title: String, value: Binding<Float>, range: ClosedRange<Float>)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)

                Spacer()

                Text(String(format: "%.1f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(
                        .secondary)
            }

            Slider(value: value, in: range)
        }
    }
}
