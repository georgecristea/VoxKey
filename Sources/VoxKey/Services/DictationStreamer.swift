import AVFoundation
import FluidAudio
import Foundation

/// Drives real-time streaming dictation. A live microphone tap feeds FluidAudio's low-latency
/// Parakeet EOU model for near-instant partial text (the live preview), while the raw audio is
/// captured so the caller can run an accurate final pass with the full 0.6B Parakeet model on
/// release (the "hybrid": snappy preview + accurate committed text). The EOU model is loaded
/// once and reused across dictations.
@MainActor
final class DictationStreamer {
    private var manager: StreamingEouAsrManager?
    private var loadedChunkSize: StreamingChunkSize?

    private var audioEngine: AVAudioEngine?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?

    private var feedTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var capturedSamples: [Float] = []
    private var isRunning = false

    private var onPartial: (@MainActor (String) -> Void)?
    private var onLevel: (@MainActor (Double) -> Void)?

    static func chunkSize(forMs milliseconds: Int) -> StreamingChunkSize {
        switch milliseconds {
        case 160: return .ms160
        case 1280: return .ms1280
        default: return .ms320
        }
    }

    /// Ensures the EOU streaming model for the requested latency is downloaded + loaded.
    /// Idempotent — returns immediately if already loaded for that chunk size.
    func prepare(chunkSizeMs: Int, modelsRoot: URL) async throws {
        let chunkSize = Self.chunkSize(forMs: chunkSizeMs)
        if manager != nil, loadedChunkSize == chunkSize { return }
        let newManager = StreamingEouAsrManager(chunkSize: chunkSize)
        try await newManager.loadModels(to: modelsRoot)
        manager = newManager
        loadedChunkSize = chunkSize
    }

    func start(
        onPartial: @escaping @MainActor (String) -> Void,
        onLevel: @escaping @MainActor (Double) -> Void) async throws
    {
        // Never run two sessions over one engine; tear any prior one down first.
        if isRunning { await cancel() }

        self.onPartial = onPartial
        self.onLevel = onLevel
        capturedSamples = []
        // No EOU model (e.g. Intel / no Neural Engine) ⇒ capture-only, no live preview.
        if let manager {
            await manager.reset()
            await manager.setPartialTranscriptCallback { [weak self] text in
                Task { @MainActor in self?.onPartial?(text) }
            }
        }

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        inputContinuation = continuation

        // Fresh engine per session — reusing one across start/stop cycles is a known source of
        // AVAudioEngine state corruption (and crashes when the mic gets wedged).
        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        feedTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in stream {
                await self.consume(buffer)
            }
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let level = DictationStreamer.rms(buffer)
            Task { @MainActor in self.onLevel?(level) }
            if let copy = DictationStreamer.copy(buffer) {
                self.inputContinuation?.yield(copy)
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // A failed start must not leave a stale tap/stream that crashes the next attempt.
            input.removeTap(onBus: 0)
            audioEngine = nil
            inputContinuation?.finish()
            inputContinuation = nil
            feedTask?.cancel()
            feedTask = nil
            isRunning = false
            throw error
        }
        isRunning = true
    }

    /// Stops capture and returns the captured 16 kHz mono samples for the accurate final pass.
    func finish() async -> [Float] {
        guard isRunning else { return capturedSamples }
        isRunning = false
        teardownAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        await feedTask?.value
        feedTask = nil
        _ = try? await manager?.finish()
        return capturedSamples
    }

    func cancel() async {
        guard isRunning else { return }
        isRunning = false
        teardownAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        await feedTask?.value
        feedTask = nil
        await manager?.reset()
        capturedSamples = []
    }

    // MARK: Per-buffer processing (ordered)

    private func consume(_ buffer: AVAudioPCMBuffer) async {
        guard let buffer16k = resampleTo16k(buffer) else {
            _ = try? await manager?.process(audioBuffer: buffer)
            return
        }
        if let channel = buffer16k.floatChannelData {
            capturedSamples.append(
                contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(buffer16k.frameLength)))
        }
        _ = try? await manager?.process(audioBuffer: buffer16k)
    }

    private func resampleTo16k(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    private func teardownAudio() {
        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frames { sum += samples[i] * samples[i] }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 1e-7))
        let clamped = max(-55, min(0, db))
        let normalized = (clamped + 55) / 55
        return Double(pow(normalized, 1.5))
    }

    nonisolated private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard
            let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
            let source = buffer.floatChannelData,
            let destination = copy.floatChannelData
        else { return nil }
        copy.frameLength = buffer.frameLength
        let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(buffer.format.channelCount) {
            memcpy(destination[channel], source[channel], bytes)
        }
        return copy
    }
}
