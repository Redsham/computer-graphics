import EngineCore
import GPUShared
import Metal
import simd

extension FrameResources {
    // MARK: - Frame data upload

    func upload(
        snapshot: RenderSnapshot, configuration: EngineConfiguration, resources: ResourceStore,
        device: any MTLDevice
    ) throws {
        if snapshot.objects.count > capacity {
            let nextCapacity = max(snapshot.objects.count, capacity * 2)

            guard
                let buffer = device.makeBuffer(
                    length: nextCapacity * MemoryLayout<GPUObject>.stride, options: .storageModeShared)
            else {
                throw EngineError.unavailable("Could not grow object buffer.")
            }

            objects = buffer
            capacity = nextCapacity
        }

        var frame = GPUFrame(
            viewProjection: snapshot.viewProjection,
            lightDirection: SIMD4(snapshot.light.direction, 0),
            lightColor: SIMD4(snapshot.light.color * snapshot.light.intensity, 1),
            parameters: SIMD4(configuration.exposure, 0, 0, 0))
        uniforms.contents().copyMemory(from: &frame, byteCount: MemoryLayout<GPUFrame>.stride)
        let destination = objects.contents().bindMemory(to: GPUObject.self, capacity: capacity)

        for (index, object) in snapshot.objects.enumerated() {
            let material = try resources.material(object.material)

            guard abs(simd_determinant(object.model)) > 0.000001 else {
                throw EngineError.unavailable("Non-invertible model transform.")
            }

            destination[index] = GPUObject(
                model: object.model, normalMatrix: object.model.inverse.transpose,
                baseColor: SIMD4(material.baseColor, 1))
        }
    }
}
