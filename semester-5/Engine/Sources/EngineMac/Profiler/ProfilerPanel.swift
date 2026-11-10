import Charts
import EngineCore
import SwiftUI

// MARK: - Profiler

@MainActor struct ProfilerPanel: View {
    @ObservedObject var session: EngineSession

    private var frames: [FrameProfile] {
        state.frozen ?? session.profileFrames
    }

    private var frameDomain: ClosedRange<UInt64> {
        let span = UInt64(max(2, session.renderer.profiles.capacity) - 1)
        let end = max(frames.last?.id ?? 0, span)

        return (end - span)...end
    }

    private var latest: FrameProfile? {
        frames.first(where: {
            $0.id == state.selectedFrameID
        }) ?? frames.last(where: {
            $0.gpuMilliseconds != nil
        }) ?? frames.last
    }

    @ObservedObject var state: ProfilerViewState

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(state.frozen == nil ? "Freeze profiler" : "Live profiler") {
                        state.frozen = state.frozen == nil ? session.profileFrames : nil
                    }

                    Button("Export…") {
                        session.exportProfiles(frames)
                    }

                    Button("Clear") {
                        session.renderer.profiles.clear()

                        session.refreshDiagnostics()
                    }

                    Toggle(
                        "GPU timestamps",
                        isOn: Binding(
                            get: {
                                session.renderer.profilingEnabled
                            },
                            set: {
                                session.renderer.profilingEnabled = $0
                            }))
                }

                Chart(frames) { frame in
                    LineMark(x: .value("Frame", frame.id), y: .value("Milliseconds", frame.cpuMilliseconds))
                        .foregroundStyle(by: .value("Stage", "CPU"))

                    if let gpu = frame.gpuMilliseconds {
                        LineMark(x: .value("Frame", frame.id), y: .value("Milliseconds", gpu))
                            .foregroundStyle(by: .value("Stage", "GPU"))
                    }
                }
                .chartXScale(domain: frameDomain)
                .chartXSelection(value: $state.selectedFrameID)
                .chartYAxisLabel("ms")
                .chartLegend(position: .bottom)
                .frame(minHeight: 115)

                let values = frames.map(\.cpuMilliseconds).sorted()

                let average: Double = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
                let percentile: Double = values.isEmpty ? 0.0 : values[Int(Double(values.count - 1) * 0.95)]

                Text(
                    String(
                        format: "CPU avg %.3f ms · p95 %.3f ms · max %.3f ms · %d frames",
                        average, percentile, values.last ?? 0,
                        values.count)
                )
                .font(.caption.monospaced())

                if let latest {
                    Text(
                        String(
                            format: "GPU wait %.3f ms · %d draws · %.2f MiB frame residency",
                            latest.waitMilliseconds,
                            latest.drawCount, Double(latest.resourceBytes) / 1_048_576)
                    )
                    .font(.caption.monospaced())

                    if latest.instrumented {
                        Text("Captured frame includes readback/instrumentation overhead.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frame \(latest?.id ?? 0)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text("CPU systems")
                        .font(.headline)

                    ForEach(latest?.systems ?? []) { timing in
                        row(timing)
                    }

                    Divider()

                    Text("CPU encoding / GPU passes")
                        .font(.headline)

                    ForEach(latest?.passesCPU ?? []) { timing in
                        row(timing)

                        if let gpu = latest?.passesGPU.first(where: {
                            $0.name == timing.name
                        }) {
                            Text(String(format: "GPU %.3f ms", gpu.milliseconds))
                                .font(.caption.monospaced())
                                .foregroundStyle(.mint)
                        }
                    }

                    if latest?.gpuMilliseconds == nil {
                        Text("GPU result pending or counters disabled.")
                            .font(.caption)
                            .foregroundStyle(
                                .secondary)
                    }
                }
            }
            .frame(width: 310)
        }
        .padding(12)
    }

    private func row(_ sample: TimingSample) -> some View {
        HStack {
            Text(sample.name)

            Spacer()

            Text(String(format: "%.3f ms", sample.milliseconds))
                .monospacedDigit()
        }
        .font(.caption)
    }
}
