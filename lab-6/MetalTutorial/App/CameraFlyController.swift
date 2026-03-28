import Cocoa
import MetalKit
import simd

final class CameraFlyController {
    private weak var view: MTKView?
    private var eventMonitors: [Any] = []

    private var pressedKeyCodes: Set<UInt16> = []
    private var leftMousePressed = false
    private let movementKeyCodes: Set<UInt16> = [0, 1, 2, 12, 13, 14, 56, 60] // A,S,D,Q,W,E,Shift

    private var yaw: Float = -.pi / 2.0
    private var pitch: Float = 0.0

    var position: simd_float3

    var moveSpeed: Float = 800.0
    var sprintMultiplier: Float = 2.5
    var mouseSensitivity: Float = 0.003

    var viewMatrix: simd_float4x4 {
        createViewMatrix(
            eyePosition: position,
            targetPosition: position + forwardVector,
            upVec: simd_float3(0.0, 1.0, 0.0)
        )
    }

    var forwardVector: simd_float3 {
        simd_normalize(simd_float3(
            cos(pitch) * cos(yaw),
            sin(pitch),
            cos(pitch) * sin(yaw)
        ))
    }

    private var right: simd_float3 {
        simd_normalize(simd_cross(forwardVector, simd_float3(0.0, 1.0, 0.0)))
    }

    init(view: MTKView, startPosition: simd_float3 = simd_float3(0.0, 4.0, 15.0)) {
        self.view = view
        self.position = startPosition
        installEventMonitors()
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
    }

    func update(deltaTime: Float) {
        let sprint = pressedKeyCodes.contains(56) || pressedKeyCodes.contains(60) // Shift (left/right)
        let speed = moveSpeed * (sprint ? sprintMultiplier : 1.0)
        let amount = speed * deltaTime

        if pressedKeyCodes.contains(13) { // W
            position += forwardVector * amount
        }
        if pressedKeyCodes.contains(1) { // S
            position -= forwardVector * amount
        }
        if pressedKeyCodes.contains(0) { // A
            position -= right * amount
        }
        if pressedKeyCodes.contains(2) { // D
            position += right * amount
        }
        if pressedKeyCodes.contains(12) { // Q
            position.y -= amount
        }
        if pressedKeyCodes.contains(14) { // E
            position.y += amount
        }
    }

    private func installEventMonitors() {
        guard let view else { return }

        view.window?.acceptsMouseMovedEvents = true

        if let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            guard self.movementKeyCodes.contains(event.keyCode) else { return event }
            self.pressedKeyCodes.insert(event.keyCode)
            return nil
        }) {
            eventMonitors.append(keyDown)
        }

        if let keyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            guard let self else { return event }
            guard self.movementKeyCodes.contains(event.keyCode) else { return event }
            self.pressedKeyCodes.remove(event.keyCode)
            return nil
        }) {
            eventMonitors.append(keyUp)
        }

        if let leftMouseDown = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            self?.leftMousePressed = true
            return event
        }) {
            eventMonitors.append(leftMouseDown)
        }

        if let leftMouseUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            self?.leftMousePressed = false
            return event
        }) {
            eventMonitors.append(leftMouseUp)
        }

        let mouseHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self, self.leftMousePressed else { return event }
            self.yaw += Float(event.deltaX) * self.mouseSensitivity
            self.pitch -= Float(event.deltaY) * self.mouseSensitivity
            self.pitch = max(-1.54, min(1.54, self.pitch))
            return event
        }

        if let mouseMoved = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: mouseHandler) {
            eventMonitors.append(mouseMoved)
        }

        if let rightDragged = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: mouseHandler) {
            eventMonitors.append(rightDragged)
        }
    }
}
