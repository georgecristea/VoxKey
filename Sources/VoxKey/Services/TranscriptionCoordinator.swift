import Foundation
import MacUtilityKit

/// Presents one transcription surface to the app while routing each operation to the engine
/// that owns the selected model: Parakeet → FluidAudio (Neural Engine), Whisper → whisper.cpp
/// (CPU). Merges both engines' status into a single `runtimeStatus` so the UI is unchanged.
@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published private(set) var runtimeStatus = ModelRuntimeStatus.initial
    @Published private(set) var isRunning = false
    @Published private(set) var setupMessage: String?

    /// The Apple Silicon / Neural Engine engine (also drives the live streaming preview).
    let fluid = FluidAudioEngine()
    /// The whisper.cpp engine (Intel tier + verbatim option). Metal on Apple Silicon, CPU on Intel.
    let whisper = WhisperCppEngine(useGPU: MUKHardware.current.isAppleSilicon)

    private func isWhisper(_ id: String) -> Bool {
        SpeechModel.model(for: id)?.engine == .whisper
    }

    private var activeEngine: any TranscriptionEngine {
        isWhisper(runtimeStatus.selectedModelID) ? whisper : fluid
    }

    func start(selectedModelID: String) {
        runtimeStatus.selectedModelID = selectedModelID
        fluid.start(selectedModelID: selectedModelID)
        whisper.start(selectedModelID: selectedModelID)
        Task { await refreshStatus() }
    }

    func stop() {
        fluid.stop()
        whisper.stop()
    }

    func refreshStatus() async {
        await fluid.refreshStatus()
        await whisper.refreshStatus()
        merge()
    }

    func selectModel(_ model: SpeechModel) async {
        runtimeStatus.selectedModelID = model.id
        if model.engine == .whisper {
            await whisper.selectModel(model)
        } else {
            await fluid.selectModel(model)
        }
        merge()
    }

    func warmSelectedModel() async {
        await activeEngine.warmSelectedModel()
        merge()
    }

    func downloadModel(_ model: SpeechModel) async {
        // Reflect the in-flight state immediately (the engine call blocks until done).
        runtimeStatus.availability[model.id] = .downloading
        if model.engine == .whisper {
            await whisper.downloadModel(model)
        } else {
            await fluid.downloadModel(model)
        }
        merge()
    }

    func deleteModel(_ model: SpeechModel) async {
        if model.engine == .whisper {
            await whisper.deleteModel(model)
        } else {
            await fluid.deleteModel(model)
        }
        merge()
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await activeEngine.transcribe(audioURL: audioURL)
    }

    /// Accurate final pass on captured samples, routed to the selected model's engine.
    func transcribe(samples: [Float], language: String) async throws -> TranscriptionResult {
        if isWhisper(runtimeStatus.selectedModelID) {
            return try await whisper.transcribe(samples: samples, language: language)
        }
        return try await fluid.transcribe(samples: samples, language: language)
    }

    private func merge() {
        var availability: [String: ModelAvailability] = [:]
        var progress: [String: Double] = [:]
        for model in SpeechModel.catalog {
            let source = model.engine == .whisper ? whisper.runtimeStatus : fluid.runtimeStatus
            availability[model.id] = source.availability[model.id] ?? .unknown
            if let value = source.downloadProgress[model.id] { progress[model.id] = value }
        }
        runtimeStatus = ModelRuntimeStatus(
            selectedModelID: runtimeStatus.selectedModelID,
            loadedModelID: activeEngine.runtimeStatus.loadedModelID,
            availability: availability,
            downloadProgress: progress,
            errorMessage: activeEngine.runtimeStatus.errorMessage)
        isRunning = fluid.isRunning || whisper.isRunning
        setupMessage = activeEngine.setupMessage
    }
}
