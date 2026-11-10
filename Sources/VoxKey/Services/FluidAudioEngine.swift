import AVFoundation
import FluidAudio
import Foundation

/// In-process transcription engine backed by FluidAudio + NVIDIA Parakeet, running on the
/// Apple Neural Engine via Core ML. Replaces the previous bundled-Python MLX-Whisper daemon:
/// no subprocess, no HTTP, no venv. Models are downloaded on demand from Hugging Face.
@MainActor
final class FluidAudioEngine: ObservableObject, TranscriptionEngine {
    @Published private(set) var isRunning = false
    @Published private(set) var runtimeStatus = ModelRuntimeStatus.initial
    @Published private(set) var setupMessage: String?

    /// The loaded Parakeet ASR actor, kept warm between transcriptions.
    private var asrManager: AsrManager?
    /// The loaded Core ML models, shared with the streaming recognizer.
    private var loadedModels: AsrModels?
    /// Which catalog model the loaded `asrManager` corresponds to.
    private var loadedModelID: String?

    /// Ensures the selected model is downloaded + loaded and returns its Core ML models
    /// for the streaming recognizer to reuse.
    func preparedModels() async throws -> AsrModels {
        try await ensureLoaded()
        guard let loadedModels else {
            throw VoxKeyError.transcriberUnavailable("The speech model is not loaded yet.")
        }
        return loadedModels
    }

    // MARK: Lifecycle

    func start(selectedModelID: String) {
        runtimeStatus.selectedModelID = selectedModelID
        migrateLegacyModels()
        Task { await refreshStatus() }
    }

    func stop() {
        isRunning = false
    }

    func refreshStatus() async {
        for model in SpeechModel.catalog {
            // Don't clobber an in-flight download.
            if runtimeStatus.availability[model.id] == .downloading { continue }
            let exists = AsrModels.modelsExist(at: modelDirectory(for: model.id), version: version(for: model.id))
            runtimeStatus.availability[model.id] = exists ? .downloaded : .notDownloaded
        }
        isRunning = true
    }

    // MARK: Model management

    func selectModel(_ model: SpeechModel) async {
        runtimeStatus.selectedModelID = model.id
    }

    func warmSelectedModel() async {
        do {
            try await ensureLoaded()
        } catch {
            setupMessage = error.localizedDescription
            runtimeStatus.errorMessage = error.localizedDescription
        }
    }

    func downloadModel(_ model: SpeechModel) async {
        runtimeStatus.availability[model.id] = .downloading
        runtimeStatus.errorMessage = nil
        do {
            let models = try await AsrModels.downloadAndLoad(
                to: modelDirectory(for: model.id), version: version(for: model.id))
            runtimeStatus.availability[model.id] = .downloaded
            // If the just-downloaded model is the selected one, keep it warm.
            if model.id == runtimeStatus.selectedModelID {
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                asrManager = manager
                loadedModelID = model.id
                runtimeStatus.loadedModelID = model.id
            }
        } catch {
            runtimeStatus.availability[model.id] = .error
            runtimeStatus.errorMessage = error.localizedDescription
            setupMessage = error.localizedDescription
        }
    }

    func deleteModel(_ model: SpeechModel) async {
        try? FileManager.default.removeItem(at: modelDirectory(for: model.id))
        if loadedModelID == model.id {
            asrManager = nil
            loadedModelID = nil
            runtimeStatus.loadedModelID = nil
        }
        runtimeStatus.availability[model.id] = .notDownloaded
    }

    // MARK: Transcription

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        let manager = try await ensureLoaded()
        // Each utterance is independent, so it gets a fresh decoder state sized for the model.
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState)
        return TranscriptionResult(
            text: result.text,
            durationMs: Int(result.duration * 1000),
            model: modelName(for: runtimeStatus.selectedModelID))
    }

    /// Accurate batch transcription of 16 kHz mono samples — used for the authoritative
    /// final transcript in the hybrid streaming flow (live preview comes from the EOU model).
    func transcribe(samples: [Float], language: String) async throws -> TranscriptionResult {
        let manager = try await ensureLoaded()
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        // Only v3 is multilingual; v2/110M are English-only, so force English there.
        let isMultilingual = runtimeStatus.selectedModelID == "parakeet-v3"
        let lang: Language? = isMultilingual
            ? (language == "auto" ? nil : Language(rawValue: language))
            : .english
        let result = try await manager.transcribe(samples, decoderState: &decoderState, language: lang)
        return TranscriptionResult(
            text: result.text,
            durationMs: Int(result.duration * 1000),
            model: modelName(for: runtimeStatus.selectedModelID))
    }

    // MARK: Helpers

    @discardableResult
    private func ensureLoaded() async throws -> AsrManager {
        if let asrManager, loadedModelID == runtimeStatus.selectedModelID {
            return asrManager
        }
        let modelVersion = version(for: runtimeStatus.selectedModelID)
        let directory = modelDirectory(for: runtimeStatus.selectedModelID)
        guard AsrModels.modelsExist(at: directory, version: modelVersion) else {
            throw VoxKeyError.transcriberUnavailable(
                "Download \(modelName(for: runtimeStatus.selectedModelID)) before dictating.")
        }
        // Models already exist on disk, so this loads rather than downloads.
        let models = try await AsrModels.downloadAndLoad(to: directory, version: modelVersion)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        loadedModels = models
        loadedModelID = runtimeStatus.selectedModelID
        runtimeStatus.loadedModelID = runtimeStatus.selectedModelID
        setupMessage = nil
        return manager
    }

    /// VoxKey-owned model directory (under Application Support/VoxKey/Models), so deletes,
    /// size accounting, and Reveal-in-Finder all point at one predictable, backup-excluded
    /// location instead of FluidAudio's default cache. Must end in the repo folder name.
    private func modelDirectory(for id: String) -> URL {
        let fallback = AsrModels.defaultCacheDirectory(for: version(for: id)).deletingLastPathComponent()
        let root = (try? AppPaths.modelsDirectory) ?? fallback
        return root.appendingPathComponent(folderName(for: id), isDirectory: true)
    }

    private func folderName(for id: String) -> String {
        switch id {
        case "parakeet-v2": return "parakeet-tdt-0.6b-v2"
        case "parakeet-110m": return "parakeet-tdt-ctc-110m"
        default: return "parakeet-tdt-0.6b-v3"
        }
    }

    /// One-time migration: move models FluidAudio previously downloaded to its default
    /// cache into VoxKey's Models directory.
    private func migrateLegacyModels() {
        let fileManager = FileManager.default
        for model in SpeechModel.catalog {
            let destination = modelDirectory(for: model.id)
            let legacy = AsrModels.defaultCacheDirectory(for: version(for: model.id))
            guard legacy.standardizedFileURL != destination.standardizedFileURL,
                fileManager.fileExists(atPath: legacy.path),
                !fileManager.fileExists(atPath: destination.path)
            else { continue }
            try? fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.moveItem(at: legacy, to: destination)
        }
    }

    private func version(for id: String) -> AsrModelVersion {
        switch id {
        case "parakeet-v2": return .v2
        case "parakeet-110m": return .tdtCtc110m
        default: return .v3
        }
    }

    private func modelName(for id: String) -> String {
        SpeechModel.catalog.first { $0.id == id }?.displayName ?? id
    }
}
