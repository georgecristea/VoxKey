import Foundation

enum SpeechModelTier: String, CaseIterable, Identifiable {
    case bestAccuracy
    case fastHighQuality
    case balanced
    case small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestAccuracy: "Best Accuracy"
        case .fastHighQuality: "Fast High Quality"
        case .balanced: "Balanced"
        case .small: "Small"
        }
    }
}

/// Which backend runs a model. Parakeet runs on FluidAudio (Apple Neural Engine);
/// Whisper runs on whisper.cpp (CPU — the Intel tier, and a verbatim option elsewhere).
enum SpeechEngineKind {
    case parakeet
    case whisper
}

struct SpeechModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let detail: String
    let downloadSizeBytes: Int64
    let tier: SpeechModelTier
    let engine: SpeechEngineKind
    let sourceURL: URL
    /// whisper.cpp ggml model filename (nil for Parakeet, which FluidAudio manages).
    let whisperFileName: String?
    /// Direct download URL for the whisper.cpp ggml model (nil for Parakeet).
    let whisperDownloadURL: URL?

    init(
        id: String,
        displayName: String,
        detail: String,
        downloadSizeBytes: Int64,
        tier: SpeechModelTier,
        engine: SpeechEngineKind,
        sourceURL: URL,
        whisperFileName: String? = nil,
        whisperDownloadURL: URL? = nil)
    {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.downloadSizeBytes = downloadSizeBytes
        self.tier = tier
        self.engine = engine
        self.sourceURL = sourceURL
        self.whisperFileName = whisperFileName
        self.whisperDownloadURL = whisperDownloadURL
    }

    var downloadSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: downloadSizeBytes, countStyle: .file)
    }

    static let catalog: [SpeechModel] = [
        SpeechModel(
            id: "parakeet-v3",
            displayName: "Parakeet v3",
            detail: "Multilingual — 25 European languages, including English. Neural Engine.",
            downloadSizeBytes: 700_000_000,
            tier: .fastHighQuality,
            engine: .parakeet,
            sourceURL: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!),
        SpeechModel(
            id: "parakeet-v2",
            displayName: "Parakeet v2",
            detail: "English-only — leanest and fastest 0.6B. Neural Engine.",
            downloadSizeBytes: 650_000_000,
            tier: .balanced,
            engine: .parakeet,
            sourceURL: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml")!),
        SpeechModel(
            id: "parakeet-110m",
            displayName: "Parakeet Lite (110M)",
            detail: "Smallest, fastest Parakeet — English, lower accuracy. Neural Engine.",
            downloadSizeBytes: 250_000_000,
            tier: .small,
            engine: .parakeet,
            sourceURL: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml")!),
        SpeechModel(
            id: "whisper-large-v3",
            displayName: "Whisper Large v3",
            detail: "Highest-accuracy verbatim Whisper, multilingual. Heaviest download.",
            downloadSizeBytes: 3_100_000_000,
            tier: .bestAccuracy,
            engine: .whisper,
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp")!,
            whisperFileName: "ggml-large-v3.bin",
            whisperDownloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!),
        SpeechModel(
            id: "whisper-small-en",
            displayName: "Whisper Small",
            detail: "English Whisper — more accurate than Base, a bit slower.",
            downloadSizeBytes: 466_000_000,
            tier: .fastHighQuality,
            engine: .whisper,
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp")!,
            whisperFileName: "ggml-small.en.bin",
            whisperDownloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!),
        SpeechModel(
            id: "whisper-base-en",
            displayName: "Whisper Base (verbatim)",
            detail: "English Whisper — keeps fillers and punctuation. Light enough for Intel Macs.",
            downloadSizeBytes: 148_000_000,
            tier: .balanced,
            engine: .whisper,
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp")!,
            whisperFileName: "ggml-base.en.bin",
            whisperDownloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!),
        SpeechModel(
            id: "whisper-tiny-en",
            displayName: "Whisper Tiny",
            detail: "English Whisper — fastest and lightest, lower accuracy. Good for Intel Macs.",
            downloadSizeBytes: 78_000_000,
            tier: .small,
            engine: .whisper,
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp")!,
            whisperFileName: "ggml-tiny.en.bin",
            whisperDownloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!),
    ]

    static let defaultID = "parakeet-v3"

    static func model(for id: String) -> SpeechModel? {
        catalog.first { $0.id == id }
    }
}

enum ModelAvailability: String, Codable, Equatable {
    case unknown
    case notDownloaded
    case downloading
    case downloaded
    case error
}

struct ModelRuntimeStatus: Equatable {
    var selectedModelID: String
    var loadedModelID: String?
    var availability: [String: ModelAvailability]
    var downloadProgress: [String: Double]
    var errorMessage: String?

    static let initial = ModelRuntimeStatus(
        selectedModelID: SpeechModel.defaultID,
        loadedModelID: nil,
        availability: Dictionary(uniqueKeysWithValues: SpeechModel.catalog.map { ($0.id, .unknown) }),
        downloadProgress: [:],
        errorMessage: nil
    )

    func availability(for model: SpeechModel) -> ModelAvailability {
        availability[model.id] ?? .unknown
    }
}
