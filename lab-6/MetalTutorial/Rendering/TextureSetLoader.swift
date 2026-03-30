import Metal
import MetalKit

struct MaterialTextureSet {
    let albedo: MTLTexture?
    let normal: MTLTexture?
    let displacement: MTLTexture?
}

final class TextureSetLoader {
    private let loader: MTKTextureLoader

    init(device: MTLDevice) {
        self.loader = MTKTextureLoader(device: device)
    }

    func loadTexture(named: String, ext: String, sRGB: Bool = false) -> MTLTexture? {
        guard let url = Bundle.main.url(forResource: named, withExtension: ext) else { return nil }
        return try? loader.newTexture(URL: url, options: [.SRGB: sRGB])
    }

    func loadTextureSet(albedo: (name: String, ext: String),
                        normal: (name: String, ext: String),
                        displacement: (name: String, ext: String)) -> MaterialTextureSet {
        MaterialTextureSet(
            albedo: loadTexture(named: albedo.name, ext: albedo.ext, sRGB: true),
            normal: loadTexture(named: normal.name, ext: normal.ext, sRGB: false),
            displacement: loadTexture(named: displacement.name, ext: displacement.ext, sRGB: false)
        )
    }
}
