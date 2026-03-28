import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    var cameraController: CameraFlyController?
    var eventMonitors: [Any] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        let cameraController = CameraFlyController(view: mtkView)
        renderer.setCameraController(cameraController)
        self.cameraController = cameraController

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
        installDebugPreviewHotkeys()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
        view.window?.acceptsMouseMovedEvents = true
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
    }

    private func installDebugPreviewHotkeys() {
        if let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            let modeByKeyCode: [UInt16: Int] = [
                122: 1, // F1 - финальный свет
                120: 2, // F2 - albedo
                99: 3,  // F3 - normal
                118: 4, // F4 - depth
                96: 5   // F5 - reconstructed world position
            ]

            if event.keyCode == 49, !event.isARepeat { // Space
                renderer.spawnImpulseLightFromCamera()
                return nil
            }

            guard let mode = modeByKeyCode[event.keyCode] else { return event }
            renderer.setDebugPreviewMode(index: mode)
            print("[Renderer] Debug preview mode -> F\(mode)")
            return nil
        }) {
            eventMonitors.append(keyDown)
        }
    }
}
