import Foundation

/// The result of transcribing a single utterance.
struct TranscriptionResult: Sendable {
    let text: String
    let durationMs: Int
    /// Human-readable name of the model that produced the text.
    let model: String
}

/// Abstraction over an on-device speech-to-text backend. Lets the app swap engines
/// (FluidAudio/Parakeet on Apple Silicon today; a whisper.cpp CPU engine for Intel later)
/// without touching `AppState` or the UI. Implementations are `@MainActor` observable
/// objects so the UI can read `runtimeStatus`/`isRunning` directly.
@MainActor
protocol TranscriptionEngine: AnyObject {
    var isRunning: Bool { get }
    var runtimeStatus: ModelRuntimeStatus { get }
    var setupMessage: String? { get }

    func start(selectedModelID: String)
    func stop()
    func refreshStatus() async
    func selectModel(_ model: SpeechModel) async
    func warmSelectedModel() async
    func downloadModel(_ model: SpeechModel) async
    func deleteModel(_ model: SpeechModel) async
    func transcribe(audioURL: URL) async throws -> TranscriptionResult
}
