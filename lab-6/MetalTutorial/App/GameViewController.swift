import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    var cameraController: CameraFlyController?
    var eventMonitors: [Any] = []
    private let hudLabel = NSTextField(labelWithString: "FPS : --\nMode: Lit")
    private var latestFPSDisplay = "--"
    private var latestModeDisplay = "Lit"

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
        renderer.onFPSUpdate = { [weak self] fps in
            DispatchQueue.main.async {
                self?.latestFPSDisplay = String(format: "%.1f", fps)
                self?.updateHUDLabel()
            }
        }
        renderer.onDebugModeUpdate = { [weak self] modeName in
            DispatchQueue.main.async {
                self?.latestModeDisplay = modeName
                self?.updateHUDLabel()
            }
        }

        let cameraController = CameraFlyController(view: mtkView)
        renderer.setCameraController(cameraController)
        self.cameraController = cameraController

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
        configureHUDLabel()
        updateHUDLabel()
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
                96: 5,  // F5 - reconstructed world position
                97: 6   // F6 - wireframe
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

    private func configureHUDLabel() {
        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        hudLabel.textColor = NSColor(white: 0.96, alpha: 1.0)
        hudLabel.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.72)
        hudLabel.drawsBackground = true
        hudLabel.isBordered = false
        hudLabel.isBezeled = false
        hudLabel.isEditable = false
        hudLabel.lineBreakMode = .byWordWrapping
        hudLabel.alignment = .left
        hudLabel.wantsLayer = true
        hudLabel.layer?.cornerRadius = 8
        hudLabel.layer?.masksToBounds = true
        hudLabel.setContentHuggingPriority(.required, for: .horizontal)
        hudLabel.setContentHuggingPriority(.required, for: .vertical)

        view.addSubview(hudLabel)

        NSLayoutConstraint.activate([
            hudLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            hudLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            hudLabel.widthAnchor.constraint(equalToConstant: 170),
            hudLabel.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func updateHUDLabel() {
        hudLabel.stringValue = "FPS : \(latestFPSDisplay)\nMode: \(latestModeDisplay)"
    }
}
