import AppKit
import EngineCore
import EngineMetal
import MetalKit
import QuartzCore
import SwiftUI
import os

@MainActor public final class EngineSession: NSObject, ObservableObject, MTKViewDelegate {
  public let world = World()
  public let renderer: MetalRenderer
  @Published public var configuration: EngineConfiguration
  @Published public private(set) var message: String?
  @Published public private(set) var fps: Double = 0
  @Published public private(set) var cpuMilliseconds: Double = 0
  @Published public private(set) var objectCount: Int = 0
  @Published public private(set) var isRenderingPaused = false
  private let store: ConfigurationStore
  private let scheduler: SystemScheduler
  private let frame = FrameContext()
  private var clock = FrameClock()
  private var applied: EngineConfiguration
  private var statsStart = CACurrentMediaTime()
  private var statsFrames = 0
  private var statsCPU = 0.0
  private var stopped = false
  private var needsSave = false
  private let logger = Logger(subsystem: "GraphicsEngine", category: "Application")
  public init(
    defaultsData: Data, settingsName: String, systems: [any EngineSystem],
    passes: [any RenderPass] = [ForwardPass(), OutputPass()]
  ) throws {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    store = try ConfigurationStore(
      defaultsData: defaultsData,
      userURL: support.appending(path: settingsName).appending(path: "settings.json"))
    let result = store.load()
    configuration = result.configuration
    applied = result.configuration
    message = result.warning
    renderer = try MetalRenderer(passes: passes)
    scheduler = SystemScheduler(systems: systems)
    super.init()
    renderer.onError = { [weak self] message in
      self?.isRenderingPaused = true
      self?.report(message)
    }
    if let warning = result.warning { logger.warning("\(warning, privacy: .public)") }
  }
  public func resetSettings() {
    configuration = store.defaults
    needsSave = true
    retry()
  }
  public func clearMessage() { message = nil }
  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    frame.aspectRatio = Float(size.width / max(size.height, 1))
  }
  public func draw(in view: MTKView) {
    guard !stopped, !isRenderingPaused, let view = view as? EngineMetalView else { return }
    let start = CACurrentMediaTime()
    frame.deltaTime = clock.tick(at: start)
    guard view.drawableSize.width > 0, view.drawableSize.height > 0,
      let drawable = view.currentDrawable
    else { return }
    do {
      let next = try configuration.validated()
      frame.configuration = next
      frame.aspectRatio = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
      frame.input = view.input.snapshot()
      scheduler.update(world: world, frame: frame)
      try renderer.render(
        snapshot: frame.snapshot, configuration: next, surface: drawable.texture, drawable: drawable
      )
      view.preferredFramesPerSecond = next.targetFPS
      if next != applied || needsSave {
        try store.save(next)
        applied = next
        needsSave = false
      }
      statsFrames += 1
      statsCPU += CACurrentMediaTime() - start
      let elapsed = CACurrentMediaTime() - statsStart
      if elapsed >= 0.3 {
        fps = Double(statsFrames) / elapsed
        cpuMilliseconds = statsCPU / Double(statsFrames) * 1000
        objectCount = frame.snapshot.objects.count
        statsFrames = 0
        statsCPU = 0
        statsStart = CACurrentMediaTime()
      }
    } catch {
      configuration = applied
      report(error.localizedDescription)
      isRenderingPaused = true
      view.isPaused = true
    }
  }
  public func activate() {
    stopped = false
    retry()
  }
  public func retry() {
    clock.reset()
    statsFrames = 0
    statsCPU = 0
    statsStart = CACurrentMediaTime()
    isRenderingPaused = false
  }
  public func shutdown() {
    guard !stopped else { return }
    stopped = true
    scheduler.stop(world: world)
    do { try renderer.waitUntilIdle() } catch { report(error.localizedDescription) }
  }
  private func report(_ message: String) {
    logger.error("\(message, privacy: .public)")
    if self.message != message { self.message = message }
  }
}
