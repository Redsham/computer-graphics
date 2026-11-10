import EngineCore
import GPUShared
import Metal
import QuartzCore

extension FrameResources {
    /// Called only after this slot's GPU completion event has signaled.
    func prepare(
        snapshot: RenderSnapshot, configuration config: EngineConfiguration,
        surface: any MTLTexture, drawable: (any CAMetalDrawable)?, resources: ResourceStore,
        device: any MTLDevice, pipeline: RenderPipelinePlan, capturing: Bool
    ) throws {
        isCapturing = capturing
        debugBuffers.removeAll()
        debugTextures.removeAll()
        drawCount = 0
        // Only this completed slot is mutated; other slots retain their previous resources.
        retained.removeAll(keepingCapacity: true)
        residency.removeAllAllocations()
        try pipeline.updateTargets(
            frame: self, size: SIMD2(surface.width, surface.height), samples: config.sampleCount)
        targets["surface"] = surface
        try upload(
            snapshot: snapshot, configuration: config, resources: resources, device: device)

        if capturing {
            inspectBuffer(
                "Frame uniforms", buffer: uniforms, stride: MemoryLayout<GPUFrame>.stride,
                schema:
                    "GPUFrame: viewProjection float4x4 @0; lightDirection float4 @64; lightColor float4 @80; parameters float4 @96"
            )
            inspectBuffer(
                "Objects", buffer: objects,
                range: 0..<(snapshot.objects.count * MemoryLayout<GPUObject>.stride),
                stride: MemoryLayout<GPUObject>.stride,
                schema: "GPUObject: model float4x4 @0; normalMatrix float4x4 @64; baseColor float4 @128")
        }

        // Declare and retain resources before GPU submission.
        residency.addAllocation(uniforms)
        residency.addAllocation(objects)

        for texture in targets.values {
            residency.addAllocation(texture)
        }

        for object in snapshot.objects {
            let mesh = try resources.mesh(object.mesh)
            residency.addAllocation(mesh.buffer)
            retained.append(mesh.buffer)

            if capturing {
                inspectBuffer(
                    "Mesh \(object.mesh.rawValue)", buffer: mesh.buffer,
                    stride: MemoryLayout<GPUVertex>.stride,
                    schema: "GPUVertex: position float4 @0; normal float4 @16")
            }
        }

        if let drawable {
            retained.append(drawable)
        }

    }
}
