import EngineCore
import EngineMetal
import SwiftUI

// MARK: - Buffer inspector

@MainActor struct BufferInspector: View {
    let buffer: CapturedBuffer
    let export: () -> Void

    @ObservedObject var state: BufferViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(
                    "\(buffer.name) · \(buffer.length) bytes · stride \(buffer.stride.map(String.init) ?? "raw")"
                )
                .font(.caption.monospaced())

                Spacer()

                Picker("Decode", selection: $state.interpretation) {
                    ForEach(["Float32", "UInt32", "Float16", "UInt8"], id: \.self) {
                        Text($0)
                            .tag($0)
                    }
                }
                .frame(width: 170)

                Stepper(
                    "Page \(state.page + 1)/\(max(1,(buffer.bytes.count + 255)/256))", value: $state.page,
                    in: 0...max(0, (buffer.bytes.count - 1) / 256)
                )
                .frame(width: 180)

                Button("Export binary…", action: export)
                    .disabled(buffer.bytes.isEmpty)
            }

            if let schema = buffer.schema {
                Text(schema)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let note = buffer.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(
                        Array(
                            stride(
                                from: state.page * 256, to: min(buffer.bytes.count, state.page * 256 + 256),
                                by: 16)),
                        id: \.self
                    ) { offset in
                        let end = min(buffer.bytes.count, offset + 16)
                        let hex = buffer.bytes[offset..<end].map {
                            String(format: "%02X", $0)
                        }.joined(
                            separator: " ")
                        Text(
                            String(format: "%08X  ", buffer.sourceOffset + offset)
                                + hex.padding(toLength: 48, withPad: " ", startingAt: 0) + "  "
                                + decode(offset: offset, end: end)
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func decode(offset: Int, end: Int) -> String {
        let size = state.interpretation == "UInt8" ? 1 : (state.interpretation == "Float16" ? 2 : 4)
        return stride(from: offset, through: end - size, by: size).map { position -> String in
            switch state.interpretation {
            case "UInt8":
                return "\(buffer.bytes[position])"
            case "Float16":
                return buffer.bytes.withUnsafeBytes { raw in
                    String(
                        format: "%.5g",
                        BinaryScalar.float16(
                            UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: position, as: UInt16.self))
                        ))
                }
            case "UInt32":
                return buffer.bytes.withUnsafeBytes {
                    "\(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: position, as: UInt32.self)))"
                }
            default:
                return buffer.bytes.withUnsafeBytes { raw in
                    let bits = UInt32(
                        littleEndian: raw.loadUnaligned(fromByteOffset: position, as: UInt32.self))
                    return String(format: "%.5g", Float(bitPattern: bits))
                }
            }
        }.joined(separator: "  ")
    }
}
