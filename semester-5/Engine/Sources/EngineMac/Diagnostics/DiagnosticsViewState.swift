import AppKit
import EngineCore
import SwiftUI

// MARK: - Tool state independent of window attachment

@MainActor final class DiagnosticsViewState {
    let console = ConsoleViewState()
    let profiler = ProfilerViewState()
    let frame = FrameDebuggerViewState()
}

@MainActor final class ConsoleViewState: ObservableObject {
    @Published var input = ""
    @Published var historyIndex: Int?
    @Published var suggestions = ""

    @Published var search = ""
    @Published var minimum = LogLevel.debug
    @Published var follow = true
    @Published var frozen: [LogEntry]?
}

@MainActor final class ProfilerViewState: ObservableObject {
    @Published var frozen: [FrameProfile]?
    @Published var selectedFrameID: UInt64?
}

@MainActor final class FrameDebuggerViewState: ObservableObject {
    @Published var passID: Int? = 0
    @Published var resourceID = ""
    private var captureID: UInt64?
    private var textures: [String: TextureViewState] = [:]
    private var buffers: [String: BufferViewState] = [:]

    func accept(captureID: UInt64) {
        guard self.captureID != captureID else {
            return
        }

        self.captureID = captureID
        passID = 0
        resourceID = ""
        textures.removeAll()
        buffers.removeAll()
    }

    func texture(_ id: String) -> TextureViewState {
        if let state = textures[id] {
            return state
        }

        let state = TextureViewState()
        textures[id] = state
        return state
    }

    func buffer(_ id: String) -> BufferViewState {
        if let state = buffers[id] {
            return state
        }

        let state = BufferViewState()
        buffers[id] = state
        return state
    }
}

@MainActor final class TextureViewState: ObservableObject {
    @Published var sample = 0
    @Published var channel = "RGB"
    @Published var autoRange = false
    @Published var zoom: CGFloat = 1
    @Published var exposure: Double = 1
    @Published var pixelX = 0
    @Published var pixelY = 0
}

@MainActor final class BufferViewState: ObservableObject {
    @Published var page = 0
    @Published var interpretation = "Float32"
}
