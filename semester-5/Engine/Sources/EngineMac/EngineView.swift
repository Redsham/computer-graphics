import EngineCore
import MetalKit
import SwiftUI
import simd

@MainActor private struct MetalViewport: NSViewRepresentable {
  @ObservedObject var session: EngineSession
  func makeNSView(context: Context) -> MTKView {
    let view = EngineMetalView(frame: .zero, device: session.renderer.metal.device)
    view.colorPixelFormat = .bgra8Unorm_srgb
    view.depthStencilPixelFormat = .invalid
    view.sampleCount = 1
    view.framebufferOnly = false
    view.preferredFramesPerSecond = session.configuration.targetFPS
    view.delegate = session
    return view
  }
  func updateNSView(_ view: MTKView, context: Context) {
    view.isPaused = session.viewportPaused
  }
  static func dismantleNSView(_ view: MTKView, coordinator: ()) {
    view.isPaused = true
    view.delegate = nil
  }
}

@MainActor public struct EngineView: View {
  @ObservedObject private var session: EngineSession
  public init(session: EngineSession) { self.session = session }
  public var body: some View {
    VStack(spacing: 0) {
      DiagnosticsToolbar(session: session)
      Divider()
      HStack(spacing: 0) {
        ZStack(alignment: .topLeading) {
          MetalViewport(session: session)
          VStack(alignment: .leading, spacing: 5) {
            Text("METAL 4").font(.caption.bold()).foregroundStyle(.mint)
            Text(
              session.simulationPaused
                ? String(
                  format: "Paused · CPU %.2f ms · objects: %d", session.cpuMilliseconds,
                  session.objectCount)
                : String(
                  format: "%.0f FPS · CPU %.2f ms · objects: %d", session.fps,
                  session.cpuMilliseconds, session.objectCount)
            )
            .font(.system(.caption, design: .monospaced))
            Text("WASD · Q/E · Right-drag to look").font(.caption).foregroundStyle(.secondary)
          }
          .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
          .padding()
        }
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Text("Renderer").font(.title2.bold())
            Text("Engine Sandbox").foregroundStyle(.secondary)
            Divider()
            Picker("Target FPS", selection: $session.configuration.targetFPS) {
              ForEach(
                Array(Set([30, 60, 120, 144, 240, session.configuration.targetFPS])).sorted(),
                id: \.self
              ) { Text("\($0)").tag($0) }
            }
            Picker("MSAA", selection: $session.configuration.sampleCount) {
              Text("1×").tag(1)
              Text("4×").tag(4)
            }.pickerStyle(.segmented)
            Toggle("Wireframe", isOn: $session.configuration.wireframe)
            ColorPicker("Background", selection: background, supportsOpacity: false)
            setting("Exposure", value: $session.configuration.exposure, range: 0.1...8)
            Divider()
            Text("Camera").font(.headline)
            setting("Field of view", value: $session.configuration.fieldOfView, range: 20...110)
            setting("Movement speed", value: $session.configuration.cameraSpeed, range: 0.1...20)
            Button("Restore defaults") { session.resetSettings() }
            if let message = session.message {
              Divider()
              Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
              if session.isRenderingPaused { Button("Retry rendering") { session.retry() } }
              Button("Dismiss") { session.clearMessage() }
            }
            Spacer(minLength: 0)
          }.padding(20)
        }.frame(width: 280)
      }
      if session.diagnosticsVisible {
        Divider()
        DiagnosticsPanel(session: session).frame(height: 340)
      }
    }
    .frame(minWidth: 1100, minHeight: 800)
    .onAppear { session.activate() }
    .onDisappear { session.shutdown() }
  }
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
        else { return }
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
        Text(String(format: "%.1f", value.wrappedValue)).monospacedDigit().foregroundStyle(
          .secondary)
      }
      Slider(value: value, in: range)
    }
  }
}
