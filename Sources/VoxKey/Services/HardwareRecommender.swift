import Foundation
import MacUtilityKit

/// Maps the detected Mac to a recommended speech model. Parakeet is light enough to run
/// on every Apple Silicon Mac, so the choice is mostly about language coverage: English-only
/// users get the leaner v2; everyone else gets the multilingual v3.
enum HardwareRecommender {
    static func recommendedModelID(
        hardware: MUKHardware = .current,
        preferredLanguages: [String] = Locale.preferredLanguages) -> String
    {
        // Parakeet needs the Neural Engine (Apple Silicon); Intel Macs use whisper.cpp on CPU.
        guard hardware.isAppleSilicon else { return "whisper-base-en" }
        let englishOnly = !preferredLanguages.isEmpty
            && preferredLanguages.allSatisfy { $0.lowercased().hasPrefix("en") }
        return englishOnly ? "parakeet-v2" : "parakeet-v3"
    }

    static func rationale(hardware: MUKHardware = .current) -> String {
        guard hardware.isAppleSilicon else {
            return "\(hardware.chipBrand) — Whisper on the CPU (no Neural Engine)."
        }
        return "\(hardware.chipBrand), \(hardware.ramGB) GB — runs on the Neural Engine."
    }
}
