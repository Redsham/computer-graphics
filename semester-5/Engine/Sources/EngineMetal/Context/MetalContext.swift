import EngineCore
import Foundation
import Metal

// MARK: - GPU context

@MainActor public final class MetalContext {
    public let device: any MTLDevice
    let queue: any MTL4CommandQueue
    let compiler: any MTL4Compiler
    let library: any MTLLibrary
    let completion: any MTLSharedEvent

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4),
            let queue = device.makeMTL4CommandQueue(), let event = device.makeSharedEvent()
        else {
            throw EngineError.unavailable("Metal 4 requires macOS 26 and a supported Apple Silicon GPU.")
        }

        self.device = device
        self.queue = queue
        completion = event
        compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        library = try device.makeDefaultLibrary(bundle: .module)
    }
}
