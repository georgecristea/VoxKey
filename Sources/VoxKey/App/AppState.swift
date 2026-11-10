import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    struct DictationOutput: Equatable {
        let id = UUID()
        let text: String
    }

    enum CaptureState: Equatable {
        case idle
        case recording
        case transcribing
        case pasted
        case error

        var title: String {
            switch self {
            case .idle: "Ready"
            case .recording: "Recording"
            case .transcribing: "Transcribing"
            case .pasted: "Pasted"
            case .error: "Needs attention"
            }
        }
    }

    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var lastMessage: MUKStatusMessage?
    @Published private(set) var microphonePermission = MUKPermissions.microphone
    @Published private(set) var accessibilityPermission = MUKPermissions.accessibility
    @Published private(set) var latestDictation: DictationOutput?
    @Published private(set) var isDictationTestActive = false
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var recordingElapsed: TimeInterval = 0
    /// Live transcript shown while streaming dictation (volatile + confirmed text).
    @Published private(set) var partialText: String = ""
    /// Model currently being loaded into memory (warmed onto the engine). Drives the
    /// "loading…" progress indicator in the model list.
    @Published private(set) var loadingModelID: String?
    /// When true, the dictation hotkey is inert until resumed.
    @Published private(set) var dictationPaused: Bool

    let settings = AppSettings()
    let launchAtLoginManager = MUKLaunchAtLoginManager(label: "com.georgecristea.VoxKey")
    let engine = TranscriptionCoordinator()
    private let hardware = MUKHardware.current

    private let pasteInjector = PasteInjector()
    private var hotkeyEngine: MUKHotkeyEngine?
    private let streamer = DictationStreamer()
    private var onboardingWindowController: OnboardingWindowController?
    /// Text already inserted into the focused app during live typing (for incremental diffs).
    private var lastTypedText = ""
    private var meterTask: Task<Void, Never>?
    private var recordingStart: Date?

    init() {
        dictationPaused = settings.dictationPaused
    }

    var selectedModel: SpeechModel {
        SpeechModel.catalog.first { $0.id == settings.selectedModelID } ?? SpeechModel.catalog[0]
    }

    func setDictationPaused(_ paused: Bool) {
        settings.setDictationPaused(paused)
        dictationPaused = paused
        if paused, captureState == .recording {
            cancelCapture()
        }
        showMessage(paused ? "Dictation paused." : "Dictation resumed.")
    }

    /// Model recommended for this Mac (chip + language coverage).
    var recommendedModelID: String { HardwareRecommender.recommendedModelID() }
    /// One-line description of the detected hardware for the models UI.
    var hardwareRationale: String { HardwareRecommender.rationale() }

    func start() {
        // A model id persisted by an older build (e.g. a Whisper id) may no longer be in
        // the catalog after the engine migration — fall back to the default.
        if !SpeechModel.catalog.contains(where: { $0.id == settings.selectedModelID }) {
            settings.setSelectedModelID(SpeechModel.defaultID)
        }
        // On first run, auto-pick the model recommended for this Mac (unless the user has
        // already chosen something other than the default).
        if !settings.hasCompletedSetup, settings.selectedModelID == SpeechModel.defaultID {
            settings.setSelectedModelID(recommendedModelID)
        }
        engine.start(selectedModelID: settings.selectedModelID)
        hotkeyEngine = MUKHotkeyEngine(
            binding: settings.hotkey,
            onDown: { [weak self] in self?.beginCapture() },
            onUp: { [weak self] in self?.endCapture() }
        )
        hotkeyEngine?.start()
        refreshPermissions()
        lastMessage = MUKStatusMessage("Hold \(hotkeyLabel) to dictate.")
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            loadingModelID = settings.selectedModelID
            await engine.warmSelectedModel()
            loadingModelID = nil
            // Warm the low-latency live-preview model (Neural Engine only).
            if hardware.isAppleSilicon {
                try? await streamer.prepare(chunkSizeMs: settings.streamingLatencyMs, modelsRoot: modelsRoot())
            }
        }
        if !settings.hasCompletedSetup {
            showOnboarding()
        }
    }

    private func modelsRoot() -> URL {
        (try? AppPaths.modelsDirectory) ?? FileManager.default.temporaryDirectory
    }

    func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(appState: self) { [weak self] in
                self?.completeOnboarding()
            }
        }
        onboardingWindowController?.showWindow(nil)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func completeOnboarding() {
        settings.setHasCompletedSetup(true)
        onboardingWindowController?.close()
        refreshPermissions()
    }

    func stop() {
        hotkeyEngine?.stop()
        Task { await self.streamer.cancel() }
        engine.stop()
    }

    /// Display label for the current push-to-talk hotkey (e.g. "fn ⌃").
    var hotkeyLabel: String { settings.hotkey.displayString }

    /// Apply a new hotkey binding live and persist it.
    func reconfigureHotkey(_ hotkey: MUKHotkey) {
        settings.setHotkey(hotkey)
        hotkeyEngine?.update(binding: hotkey)
        showMessage("Hotkey set to \(hotkey.displayString).", tone: .success)
    }

    func refreshPermissions() {
        microphonePermission = MUKPermissions.microphone
        accessibilityPermission = MUKPermissions.accessibility
    }

    func requestMicrophonePermission() {
        Task {
            microphonePermission = await MUKPermissions.requestMicrophone()
            if microphonePermission != .granted {
                showMessage("Microphone \(microphonePermission.label.lowercased()).", tone: microphonePermission.tone)
            }
        }
    }

    func requestAccessibilityPermission() {
        refreshPermissions()
        MUKPermissions.promptForAccessibility()
        if accessibilityPermission != .granted {
            openAccessibilitySettings()
        }
        Task {
            await pollAccessibilityPermission()
        }
    }

    func beginCapture() {
        guard !dictationPaused else { return }
        refreshPermissions()
        guard microphonePermission == .granted else {
            captureState = .error
            showMessage("Grant Microphone permission before dictating.", tone: .warning)
            requestMicrophonePermission()
            return
        }
        guard accessibilityPermission == .granted else {
            captureState = .error
            showMessage("Grant Accessibility permission so VoxKey can paste.", tone: .warning)
            requestAccessibilityPermission()
            return
        }

        partialText = ""
        lastTypedText = ""
        captureState = .recording
        startMetering()
        lastMessage = MUKStatusMessage("Listening… release \(hotkeyLabel) to \(settings.liveTyping ? "stop" : "paste").")
        Task { await beginStreaming() }
    }

    private func beginStreaming() async {
        do {
            await engine.warmSelectedModel()  // ensure the final model (Parakeet or Whisper) is loaded
            if hardware.isAppleSilicon {
                try? await streamer.prepare(chunkSizeMs: settings.streamingLatencyMs, modelsRoot: modelsRoot())
            }
            try await streamer.start(
                onPartial: { [weak self] text in self?.handlePartial(text) },
                onLevel: { [weak self] level in self?.inputLevel = level })
            // The user may have released the key while models were loading.
            if captureState != .recording {
                await streamer.cancel()
            }
        } catch {
            stopMetering()
            captureState = .error
            showMessage(error.localizedDescription, tone: .error)
        }
    }

    func endCapture() {
        guard captureState == .recording else { return }
        stopMetering()
        captureState = .transcribing
        Task { await finishStreaming() }
    }

    func cancelCapture() {
        stopMetering()
        partialText = ""
        if settings.liveTyping, !lastTypedText.isEmpty {
            pasteInjector.deleteBackward(lastTypedText.count)
        }
        lastTypedText = ""
        Task { await streamer.cancel() }
        captureState = .idle
        showMessage("Recording canceled.")
    }

    private func handlePartial(_ text: String) {
        partialText = text
        if settings.liveTyping {
            applyLiveText(text)
        }
    }

    /// Reconciles the focused app's text to `newText` by deleting the changed tail and
    /// typing the new suffix — the standard live-dictation incremental update.
    private func applyLiveText(_ newText: String) {
        let common = lastTypedText.commonPrefix(with: newText)
        let deleteCount = lastTypedText.count - common.count
        let toType = String(newText.dropFirst(common.count))
        if deleteCount > 0 { pasteInjector.deleteBackward(deleteCount) }
        if !toType.isEmpty { pasteInjector.typeText(toType) }
        lastTypedText = newText
    }

    func setDictationTestActive(_ active: Bool) {
        isDictationTestActive = active
    }

    func selectModel(_ model: SpeechModel) {
        settings.setSelectedModelID(model.id)
        Task {
            await engine.selectModel(model)
            loadingModelID = model.id
            await engine.warmSelectedModel()
            loadingModelID = nil
        }
    }

    func downloadModel(_ model: SpeechModel) {
        Task {
            await engine.downloadModel(model)
            await pollModelDownload(model)
            if model.id == engine.runtimeStatus.selectedModelID {
                loadingModelID = model.id
                await engine.warmSelectedModel()
                loadingModelID = nil
            }
        }
    }

    func deleteModel(_ model: SpeechModel) {
        Task {
            await engine.deleteModel(model)
        }
    }

    func refreshModelStatus() {
        Task {
            await engine.refreshStatus()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            settings.setLaunchAtLogin(launchAtLoginManager.isEnabled)
            showMessage(enabled ? "Launch at login enabled." : "Launch at login disabled.")
        } catch {
            showMessage("Could not update launch at login: \(error.localizedDescription)", tone: .error)
        }
    }

    func setSendEnterAfterDictation(_ enabled: Bool) {
        settings.setSendEnterAfterDictation(enabled)
        showMessage(enabled ? "Return after dictation enabled." : "Return after dictation disabled.")
    }

    func setLiveTyping(_ enabled: Bool) {
        settings.setLiveTyping(enabled)
        showMessage(enabled ? "Live typing enabled." : "Live typing disabled.")
    }

    func setStreamingLatencyMs(_ value: Int) {
        settings.setStreamingLatencyMs(value)
        Task { try? await streamer.prepare(chunkSizeMs: value, modelsRoot: modelsRoot()) }
    }

    func setDictationLanguage(_ code: String) {
        settings.setDictationLanguage(code)
        showMessage("Language set to \(DictationLanguage.name(for: code)).")
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func finishStreaming() async {
        let samples = await streamer.finish()
        do {
            let text: String
            if samples.isEmpty {
                text = ""
            } else {
                let result = try await engine.transcribe(samples: samples, language: settings.dictationLanguage)
                text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            partialText = ""
            guard !text.isEmpty else {
                if settings.liveTyping, !lastTypedText.isEmpty {
                    pasteInjector.deleteBackward(lastTypedText.count)
                }
                lastTypedText = ""
                captureState = .idle
                showMessage("No speech detected.", tone: .warning)
                return
            }
            if isDictationTestActive {
                latestDictation = DictationOutput(text: settings.sendEnterAfterDictation ? "\(text)\n" : text)
            }
            if settings.liveTyping {
                applyLiveText(text)  // reconcile to the authoritative final transcript
                lastTypedText = ""
                if settings.sendEnterAfterDictation {
                    // Let the typed text and the just-released hotkey settle before Return,
                    // otherwise the Return races the keystrokes and is dropped intermittently.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.pasteInjector.sendReturn()
                    }
                }
            } else {
                try pasteInjector.paste(text, sendEnterAfterPaste: settings.sendEnterAfterDictation)
            }
            captureState = .pasted
            showMessage("Dictated \(text.count) characters using \(selectedModel.displayName).", tone: .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if self.captureState == .pasted {
                    self.captureState = .idle
                }
            }
        } catch {
            partialText = ""
            lastTypedText = ""
            captureState = .error
            showMessage(error.localizedDescription, tone: .error)
        }
    }

    private func startMetering() {
        recordingStart = Date()
        recordingElapsed = 0
        inputLevel = 0
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let start = self.recordingStart {
                    self.recordingElapsed = Date().timeIntervalSince(start)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        recordingStart = nil
        inputLevel = 0
    }

    private func showMessage(_ text: String, tone: MUKStatusMessage.Tone = .neutral) {
        lastMessage = MUKStatusMessage(text, tone: tone)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func pollAccessibilityPermission() async {
        for _ in 0..<30 {
            refreshPermissions()
            if accessibilityPermission == .granted {
                showMessage("Accessibility permission allowed.", tone: .success)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        showMessage("VoxKey still needs Accessibility permission to paste.", tone: .warning)
    }

    private func pollModelDownload(_ model: SpeechModel) async {
        for _ in 0..<120 {
            let status = engine.runtimeStatus.availability(for: model)
            guard status == .downloading else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await engine.refreshStatus()
        }
    }
}
