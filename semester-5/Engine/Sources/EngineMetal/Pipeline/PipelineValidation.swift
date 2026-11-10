import EngineCore
import Metal

// MARK: - Pipeline validation

public enum PipelineValidation {
    /// Surface is an externally supplied write target, not an initialized input.
    public static func validate(_ declarations: [PassDeclaration]) throws -> [TextureContract] {
        var available: [String: TextureContract] = [:]

        for declaration in declarations {
            for input in declaration.inputs {
                guard input.name != "surface", available[input.name] == input else {
                    throw EngineError.invalidPipeline(
                        "\(declaration.name): missing or incompatible input \(input.name).")
                }
            }

            for output in declaration.outputs {
                guard !output.name.isEmpty, output.samples > 0, output.format != .invalid,
                    available[output.name] == nil
                else {
                    throw EngineError.invalidPipeline(
                        "\(declaration.name): invalid or duplicate output \(output.name).")
                }

                if output.name == "surface" && (output.format != .bgra8Unorm_srgb || output.samples != 1) {
                    throw EngineError.invalidPipeline("Surface must be single-sample BGRA8 sRGB.")
                }

                available[output.name] = output
            }
        }

        guard declarations.last?.outputs.contains(where: { $0.name == "surface" }) == true else {
            throw EngineError.invalidPipeline("Pipeline must produce surface.")
        }

        return available.values.sorted { $0.name < $1.name }
    }
}
