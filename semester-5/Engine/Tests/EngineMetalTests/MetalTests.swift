import EngineCore
import EngineMetal
import Metal
import XCTest
import simd

@MainActor final class MetalTests: XCTestCase {
  func testPassContractsRejectMissingInputsFormatsAndDuplicateOutputs() throws {
    let hdr = TextureContract("hdr", format: .rgba16Float)
    let surface = TextureContract("surface", format: .bgra8Unorm_srgb)
    let forward = PassDeclaration(name: "Forward", outputs: [hdr])
    let output = PassDeclaration(name: "Output", inputs: [hdr], outputs: [surface])
    XCTAssertEqual(try PipelineValidation.validate([forward, output]).count, 2)
    XCTAssertThrowsError(try PipelineValidation.validate([output, forward]))
    XCTAssertThrowsError(try PipelineValidation.validate([forward, forward, output]))
    XCTAssertThrowsError(
      try PipelineValidation.validate([
        forward,
        PassDeclaration(
          name: "Wrong", inputs: [TextureContract("hdr", format: .rgba8Unorm)], outputs: [surface]),
      ]))
    XCTAssertThrowsError(
      try PipelineValidation.validate([
        forward,
        PassDeclaration(
          name: "Wrong samples", inputs: [TextureContract("hdr", format: .rgba16Float, samples: 4)],
          outputs: [surface]),
      ]))
  }
  func testOffscreenGeometryDepthExposureAndFrameReuse() throws {
    guard MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true else {
      throw XCTSkip("Metal 4 GPU required")
    }
    let renderer = try MetalRenderer()
    let device = renderer.metal.device
    let cube = try renderer.resources.makeCube()
    let red = renderer.resources.makeMaterial(Material(baseColor: SIMD3(0.9, 0.03, 0.03)))
    let blue = renderer.resources.makeMaterial(Material(baseColor: SIMD3(0.03, 0.03, 0.9)))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm_srgb, width: 128, height: 128, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget]
    let surface = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    var snapshot = RenderSnapshot()
    snapshot.viewProjection =
      Math.perspective(fovDegrees: 60, aspect: 1, near: 0.1, far: 100)
      * Math.translation(SIMD3(0, 0, -4))
    let front = RenderObject(mesh: cube, material: red, model: Math.translation(SIMD3(0, 0, 0.5)))
    let back = RenderObject(mesh: cube, material: blue, model: Math.translation(SIMD3(0, 0, -0.5)))
    snapshot.objects = [front, back]  // Farther geometry is submitted last: depth must reject it.
    var config = EngineConfiguration()
    config.background = .zero
    var gpuErrors: [String] = []
    renderer.onError = { gpuErrors.append($0) }
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
      var rgba = [UInt8](repeating: 0, count: 4)
      surface.getBytes(&rgba, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
      return rgba
    }
    try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
    try renderer.waitUntilIdle()
    let bright = pixel(64, 64)
    XCTAssertGreaterThan(
      Int(bright[2]), Int(bright[0]) * 2, "Near red cube must occlude far blue cube")
    XCTAssertGreaterThan(bright[2], 80)
    XCTAssertEqual(pixel(0, 0)[0], 0)
    snapshot.objects = [back, front]
    config.exposure = 0.2
    try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
    try renderer.waitUntilIdle()
    let dark = pixel(64, 64)
    XCTAssertLessThan(dark[2], bright[2])
    // More than three submissions and live MSAA changes exercise every slot's safe reuse.
    for index in 0..<12 {
      config.sampleCount = index.isMultiple(of: 2) ? 4 : 1
      config.wireframe = index.isMultiple(of: 3)
      try renderer.render(snapshot: snapshot, configuration: config, surface: surface)
    }
    try renderer.waitUntilIdle()
    try renderer.render(snapshot: snapshot, configuration: config, surface: nil)
    let resizedDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm_srgb, width: 192, height: 96, mipmapped: false)
    resizedDescriptor.storageMode = .shared
    resizedDescriptor.usage = [.renderTarget]
    let resized = try XCTUnwrap(device.makeTexture(descriptor: resizedDescriptor))
    try renderer.render(snapshot: snapshot, configuration: config, surface: resized)
    // Removing a submitted mesh must not release buffers still used by the GPU.
    renderer.resources.removeMesh(cube)
    try renderer.waitUntilIdle()
    XCTAssertThrowsError(
      try renderer.render(snapshot: snapshot, configuration: config, surface: resized))
    snapshot.objects = []
    try renderer.render(snapshot: snapshot, configuration: config, surface: resized)
    try renderer.waitUntilIdle()
    XCTAssertTrue(gpuErrors.isEmpty)
  }
}
