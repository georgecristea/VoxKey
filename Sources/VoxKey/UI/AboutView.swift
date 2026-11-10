import MacUtilityKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    MUKBrandIcon(symbol: "waveform", size: 52)
                    Text("VoxKey")
                        .font(.title3.weight(.semibold))
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Private on-device voice typing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                MUKCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("© 2026 DeepDive Solna AB · MIT License")
                            .font(.callout.weight(.medium))
                        Text("Free and open source. VoxKey transcribes your voice locally on this Mac; audio is never uploaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MUKCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Acknowledgements")
                            .font(.subheadline.weight(.semibold))
                        ForEach(acknowledgements, id: \.name) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.caption.weight(.medium))
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? "1.0"
    }

    private struct Acknowledgement {
        let name: String
        let detail: String
    }

    private var acknowledgements: [Acknowledgement] {
        [
            Acknowledgement(
                name: "NVIDIA Parakeet",
                detail: "Speech recognition models. © NVIDIA Corporation. TDT 0.6B v2 / v3 and TDT-CTC 110M: CC-BY-4.0. Realtime EOU 120M (live preview): NVIDIA Open Model License. Converted to Apple Core ML by FluidInference."),
            Acknowledgement(
                name: "FluidAudio",
                detail: "On-device speech recognition framework (Core ML / Neural Engine). © FluidInference. Apache License 2.0."),
            Acknowledgement(
                name: "whisper.cpp + OpenAI Whisper",
                detail: "Verbatim speech recognition (Metal on Apple Silicon, CPU on Intel). © Georgi Gerganov & ggml authors and © OpenAI. MIT License."),
            Acknowledgement(
                name: "MacUtilityKit",
                detail: "Shared macOS UI toolkit by DeepDive Solna AB. MIT License.")
        ]
    }
}
