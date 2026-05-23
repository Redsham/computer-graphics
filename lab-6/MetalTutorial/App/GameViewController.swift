import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    var cameraController: CameraFlyController?
    var eventMonitors: [Any] = []
    private let hudLabel = NSTextField(labelWithString: "FPS : --\nMode: Lit")
    private let thrustLabel = NSTextField(labelWithString: "Thrust 72%")
    private let thrustSlider = NSSlider(value: 0.72, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private var latestFPSDisplay = "--"
    private var latestModeDisplay = "Lit"
    private var latestThrustDisplay = "72%"
    private var latestCullingDisplay = "Culling: Off\nOctree : Off\nSplit  : Off\nObjects: --\nNodes  : --"

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
        renderer.onCullingStateUpdate = { [weak self] state in
            DispatchQueue.main.async {
                self?.latestCullingDisplay = Self.formatCullingState(state)
                self?.updateHUDLabel()
            }
        }
        renderer.onThrustUpdate = { [weak self] thrust in
            DispatchQueue.main.async {
                self?.latestThrustDisplay = Self.formatThrust(thrust)
                self?.thrustSlider.floatValue = thrust
                self?.thrustLabel.stringValue = "Thrust \(Self.formatThrust(thrust))"
                self?.updateHUDLabel()
            }
        }

        let cameraController = CameraFlyController(view: mtkView)
        renderer.setCameraController(cameraController)
        self.cameraController = cameraController

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
        configureHUDLabel()
        configureThrustControls()
        updateHUDLabel()
        renderer.setRocketThrust(Float(thrustSlider.floatValue))
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

            if event.keyCode == 98, !event.isARepeat { // F7
                renderer.toggleFrustumCulling()
                return nil
            }
            if event.keyCode == 100, !event.isARepeat { // F8
                renderer.toggleOctreeCulling()
                return nil
            }
            if event.keyCode == 101, !event.isARepeat { // F9
                renderer.toggleSplitScreenDebug()
                return nil
            }

            if let characters = event.charactersIgnoringModifiers, !event.isARepeat {
                if characters == "+" || characters == "=" {
                    renderer.adjustRocketThrust(by: 0.05)
                    return nil
                }
                if characters == "-" || characters == "_" {
                    renderer.adjustRocketThrust(by: -0.05)
                    return nil
                }
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
            hudLabel.widthAnchor.constraint(equalToConstant: 260),
            hudLabel.heightAnchor.constraint(equalToConstant: 184)
        ])
    }

    private func updateHUDLabel() {
        hudLabel.stringValue = "FPS : \(latestFPSDisplay)\nMode: \(latestModeDisplay)\nThrust: \(latestThrustDisplay)\n\(latestCullingDisplay)"
    }

    private func configureThrustControls() {
        thrustLabel.translatesAutoresizingMaskIntoConstraints = false
        thrustLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        thrustLabel.textColor = NSColor(white: 0.96, alpha: 1.0)
        thrustLabel.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.72)
        thrustLabel.drawsBackground = true
        thrustLabel.isBordered = false
        thrustLabel.isBezeled = false
        thrustLabel.isEditable = false
        thrustLabel.alignment = .center
        thrustLabel.wantsLayer = true
        thrustLabel.layer?.cornerRadius = 6
        thrustLabel.layer?.masksToBounds = true

        thrustSlider.translatesAutoresizingMaskIntoConstraints = false
        thrustSlider.target = self
        thrustSlider.action = #selector(thrustSliderChanged(_:))
        thrustSlider.isContinuous = true

        view.addSubview(thrustLabel)
        view.addSubview(thrustSlider)

        NSLayoutConstraint.activate([
            thrustLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            thrustLabel.topAnchor.constraint(equalTo: hudLabel.bottomAnchor, constant: 10),
            thrustLabel.widthAnchor.constraint(equalToConstant: 132),
            thrustLabel.heightAnchor.constraint(equalToConstant: 28),
            thrustSlider.leadingAnchor.constraint(equalTo: thrustLabel.trailingAnchor, constant: 10),
            thrustSlider.centerYAnchor.constraint(equalTo: thrustLabel.centerYAnchor),
            thrustSlider.widthAnchor.constraint(equalToConstant: 188)
        ])
    }

    @objc private func thrustSliderChanged(_ sender: NSSlider) {
        renderer.setRocketThrust(sender.floatValue)
    }

    private static func formatCullingState(_ state: RendererCullingHUDState) -> String {
        let culling = state.frustumEnabled ? "On" : "Off"
        let octree = state.octreeEnabled ? "On" : "Off"
        let split = state.splitDebugEnabled ? "On" : "Off"
        let stats = state.stats
        var lines = """
        Culling: \(culling)
        Octree : \(octree)
        Split  : \(split)
        Objects: \(stats.visibleObjects)/\(stats.totalObjects)
        Culled : \(stats.culledObjects)  Nodes: \(stats.visitedOctreeNodes)
        """
        if let sceneStatus = state.sceneStatus {
            lines += "\n\(sceneStatus)"
        }
        return lines
    }

    private static func formatThrust(_ thrust: Float) -> String {
        "\(Int((max(0.0, min(1.0, thrust)) * 100.0).rounded()))%"
    }
}
