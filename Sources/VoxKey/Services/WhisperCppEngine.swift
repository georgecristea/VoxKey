import AVFoundation
import Foundation
import whisper

/// Batch transcription engine backed by whisper.cpp (CPU). Used for Intel Macs (no Neural
/// Engine) and as an optional verbatim-Whisper engine on Apple Silicon. ggml models are
/// downloaded from Hugging Face. Heavy inference runs off the main actor in `WhisperRunner`.
@MainActor
final class WhisperCppEngine: ObservableObject, TranscriptionEngine {
    @Published private(set) var isRunning = false
    @Published private(set) var runtimeStatus = ModelRuntimeStatus.initial
    @Published private(set) var setupMessage: String?

    private let runner = WhisperRunner()
    private var loadedModelID: String?
    private let useGPU: Bool

    init(useGPU: Bool = false) {
        self.useGPU = useGPU
    }

    private var whisperModels: [SpeechModel] {
        SpeechModel.catalog.filter { $0.engine == .whisper }
    }

    func start(selectedModelID: String) {
        runtimeStatus.selectedModelID = selectedModelID
        Task { await refreshStatus() }
    }

    func stop() { isRunning = false }

    func refreshStatus() async {
        for model in whisperModels {
            if runtimeStatus.availability[model.id] == .downloading { continue }
            let exists = FileManager.default.fileExists(atPath: modelPath(for: model).path)
            runtimeStatus.availability[model.id] = exists ? .downloaded : .notDownloaded
        }
        isRunning = true
    }

    func selectModel(_ model: SpeechModel) async {
        runtimeStatus.selectedModelID = model.id
    }

    func warmSelectedModel() async {
        guard let model = SpeechModel.model(for: runtimeStatus.selectedModelID), model.engine == .whisper else {
            return
        }
        await loadIfNeeded(model)
    }

    func downloadModel(_ model: SpeechModel) async {
        guard model.engine == .whisper, let url = model.whisperDownloadURL else { return }
        runtimeStatus.availability[model.id] = .downloading
        runtimeStatus.errorMessage = nil
        do {
            let destination = modelPath(for: model)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            runtimeStatus.availability[model.id] = .downloaded
        } catch {
            runtimeStatus.availability[model.id] = .error
            runtimeStatus.errorMessage = error.localizedDescription
            setupMessage = error.localizedDescription
        }
    }

    func deleteModel(_ model: SpeechModel) async {
        try? FileManager.default.removeItem(at: modelPath(for: model))
        if loadedModelID == model.id {
            await runner.free()
            loadedModelID = nil
            runtimeStatus.loadedModelID = nil
        }
        runtimeStatus.availability[model.id] = .notDownloaded
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        let samples = try WhisperCppEngine.loadPCM16kMono(audioURL)
        return try await transcribe(samples: samples, language: "en")
    }

    func transcribe(samples: [Float], language: String) async throws -> TranscriptionResult {
        guard let model = SpeechModel.model(for: runtimeStatus.selectedModelID), model.engine == .whisper else {
            throw VoxKeyError.transcriberUnavailable("No Whisper model selected.")
        }
        await loadIfNeeded(model)
        guard loadedModelID == model.id else {
            throw VoxKeyError.transcriberUnavailable("Download \(model.displayName) before dictating.")
        }
        // `.en` builds are English-only and ignore the language choice.
        let isEnglishOnly = model.whisperFileName?.contains(".en") ?? true
        let effective = isEnglishOnly ? "en" : language
        let start = Date()
        let text = try await runner.transcribe(samples: samples, language: effective)
        return TranscriptionResult(
            text: text, durationMs: Int(Date().timeIntervalSince(start) * 1000), model: model.displayName)
    }

    private func loadIfNeeded(_ model: SpeechModel) async {
        if loadedModelID == model.id { return }
        let path = modelPath(for: model)
        guard FileManager.default.fileExists(atPath: path.path) else {
            setupMessage = "Download \(model.displayName) before dictating."
            return
        }
        do {
            try await runner.load(modelPath: path.path, useGPU: useGPU)
            loadedModelID = model.id
            runtimeStatus.loadedModelID = model.id
            setupMessage = nil
        } catch {
            setupMessage = error.localizedDescription
            runtimeStatus.errorMessage = error.localizedDescription
        }
    }

    private func modelPath(for model: SpeechModel) -> URL {
        let root = (try? AppPaths.modelsDirectory) ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("whisper", isDirectory: true)
            .appendingPathComponent(model.whisperFileName ?? "\(model.id).bin")
    }

    static func loadPCM16kMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else {
            return try convert(url)
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }

    private static func convert(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard
            let converter = AVAudioConverter(from: file.processingFormat, to: outFormat),
            let inBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: inBuffer)
        let ratio = 16000.0 / file.processingFormat.sampleRate
        guard
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormat,
                frameCapacity: AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1024)
        else { return [] }
        var fed = false
        converter.convert(to: outBuffer, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return inBuffer
        }
        guard let channel = outBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(outBuffer.frameLength)))
    }
}

/// Owns the whisper.cpp context and runs blocking inference off the main actor.
actor WhisperRunner {
    private var ctx: OpaquePointer?

    func load(modelPath: String, useGPU: Bool) throws {
        free()
        var params = whisper_context_default_params()
        params.use_gpu = useGPU
        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw VoxKeyError.transcriberUnavailable("Failed to load the Whisper model.")
        }
        ctx = context
    }

    func transcribe(samples: [Float], language: String) throws -> String {
        guard let ctx else { throw VoxKeyError.transcriberUnavailable("Whisper model not loaded.") }
        guard samples.count >= 1600 else { return "" }  // whisper needs ~>0.1s of audio
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.no_timestamps = true
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        // The language C-string must stay alive for the whole whisper_full call.
        let text = try language.withCString { langPtr -> String in
            params.language = langPtr
            let rc = samples.withUnsafeBufferPointer {
                whisper_full(ctx, params, $0.baseAddress, Int32($0.count))
            }
            guard rc == 0 else { throw VoxKeyError.transcriberUnavailable("Whisper transcription failed.") }
            var collected = ""
            for i in 0..<whisper_full_n_segments(ctx) {
                if let cString = whisper_full_get_segment_text(ctx, i) {
                    collected += String(cString: cString)
                }
            }
            return collected
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func free() {
        if let ctx {
            whisper_free(ctx)
            self.ctx = nil
        }
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }
}
