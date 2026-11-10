import AppKit
import EngineCore
import MetalKit

@MainActor final class InputState {
  var keys: Set<UInt16> = []
  var look = SIMD2<Float>.zero
  var looking = false
  func reset() {
    keys.removeAll()
    look = .zero
    looking = false
  }
  func snapshot() -> InputSnapshot {
    defer { look = .zero }
    func axis(_ positive: UInt16, _ negative: UInt16) -> Float {
      (keys.contains(positive) ? 1 : 0) - (keys.contains(negative) ? 1 : 0)
    }
    return InputSnapshot(movement: SIMD3(axis(2, 0), axis(14, 12), axis(1, 13)), look: look)
  }
}
@MainActor final class EngineMetalView: MTKView {
  let input = InputState()
  override var acceptsFirstResponder: Bool { true }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    input.reset()
    if let window {
      NotificationCenter.default.addObserver(
        self, selector: #selector(lostFocus), name: NSWindow.didResignKeyNotification,
        object: window)
    }
  }
  @objc private func lostFocus() { input.reset() }
  override func resignFirstResponder() -> Bool {
    input.reset()
    return super.resignFirstResponder()
  }
  override func keyDown(with event: NSEvent) {
    if [0, 1, 2, 12, 13, 14].contains(event.keyCode) {
      input.keys.insert(event.keyCode)
    } else {
      super.keyDown(with: event)
    }
  }
  override func keyUp(with event: NSEvent) { input.keys.remove(event.keyCode) }
  override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
  override func rightMouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    input.looking = true
  }
  override func rightMouseUp(with event: NSEvent) { input.looking = false }
  override func rightMouseDragged(with event: NSEvent) {
    if input.looking { input.look += SIMD2(Float(event.deltaX), Float(event.deltaY)) }
  }
}
