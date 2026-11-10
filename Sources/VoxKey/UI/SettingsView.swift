import MacUtilityKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onShowAbout: () -> Void

    @State private var launchAtLogin: Bool
    @State private var sendEnterAfterDictation: Bool
    @State private var liveTyping: Bool
    @State private var streamingLatencyMs: Int
    @State private var dictationLanguage: String

    init(appState: AppState, onShowAbout: @escaping () -> Void) {
        self.appState = appState
        self.onShowAbout = onShowAbout
        _launchAtLogin = State(initialValue: appState.launchAtLoginManager.isEnabled)
        _sendEnterAfterDictation = State(initialValue: appState.settings.sendEnterAfterDictation)
        _liveTyping = State(initialValue: appState.settings.liveTyping)
        _streamingLatencyMs = State(initialValue: appState.settings.streamingLatencyMs)
        _dictationLanguage = State(initialValue: appState.settings.dictationLanguage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Capture")

                MUKSettingsRow(
                    title: "Hotkey",
                    detail: "Hold to record, release to paste.",
                    systemImage: "keyboard")
                {
                    MUKHotkeyRecorder(hotkey: hotkeyBinding)
                }

                MUKSettingsRow(
                    title: "Language",
                    detail: "Spoken language for multilingual models (Parakeet v3, Whisper Large).",
                    systemImage: "globe")
                {
                    Picker("", selection: dictationLanguageBinding) {
                        ForEach(DictationLanguage.options, id: \.code) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }

                MUKSettingsRow(
                    title: "Microphone",
                    detail: "Required for hold-to-talk recording.",
                    systemImage: "mic")
                {
                    Button(appState.microphonePermission == .granted ? "Allowed" : "Grant") {
                        appState.requestMicrophonePermission()
                    }
                }

                MUKSettingsRow(
                    title: "Accessibility",
                    detail: "Required to paste into the focused app.",
                    systemImage: "cursorarrow.click")
                {
                    Button(accessibilityButtonTitle) {
                        appState.requestAccessibilityPermission()
                    }
                }

                sectionHeader("Behavior")

                MUKSettingsRow(
                    title: "Launch at login",
                    detail: "Start VoxKey when you sign in.",
                    systemImage: "power")
                {
                    Toggle("", isOn: launchBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                MUKSettingsRow(
                    title: "Type as I speak",
                    detail: "Insert text live while dictating instead of pasting on release.",
                    systemImage: "character.cursor.ibeam")
                {
                    Toggle("", isOn: liveTypingBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if liveTyping {
                    Text("Live text may skip punctuation as you speak — it's corrected when you finish dictating.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }

                MUKSettingsRow(
                    title: "Live preview speed",
                    detail: "How quickly text appears as you speak.",
                    systemImage: "gauge.with.dots.needle.67percent")
                {
                    Picker("", selection: streamingLatencyBinding) {
                        Text("Fast").tag(160)
                        Text("Balanced").tag(320)
                        Text("Steady").tag(1280)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                MUKSettingsRow(
                    title: "Send Return",
                    detail: "Press Return after each transcription.",
                    systemImage: "return")
                {
                    Toggle("", isOn: sendEnterBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                sectionHeader("Engine")

                MUKSettingsRow(
                    title: "Transcriber setup",
                    detail: appState.engine.setupMessage ?? "Local on-device transcription.",
                    systemImage: "cpu")
                {
                    Button("Refresh") {
                        appState.engine.start(selectedModelID: appState.settings.selectedModelID)
                        appState.refreshModelStatus()
                    }
                }

                MUKSettingsRow(
                    title: "Permissions & setup",
                    detail: "Re-run the first-run setup checklist.",
                    systemImage: "checklist")
                {
                    Button("Open") { appState.showOnboarding() }
                }

                sectionHeader("Test")
                DictationTestView(appState: appState)

                sectionHeader("About")
                Button(action: onShowAbout) {
                    MUKSettingsRow(
                        title: "About VoxKey",
                        detail: "Version, company, and acknowledgements.",
                        systemImage: "info.circle")
                    {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .onAppear {
            appState.refreshPermissions()
            launchAtLogin = appState.launchAtLoginManager.isEnabled
            sendEnterAfterDictation = appState.settings.sendEnterAfterDictation
            liveTyping = appState.settings.liveTyping
            streamingLatencyMs = appState.settings.streamingLatencyMs
            dictationLanguage = appState.settings.dictationLanguage
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
            .padding(.leading, 4)
    }

    private var hotkeyBinding: Binding<MUKHotkey> {
        Binding(
            get: { appState.settings.hotkey },
            set: { appState.reconfigureHotkey($0) }
        )
    }

    private var accessibilityButtonTitle: String {
        switch appState.accessibilityPermission {
        case .granted: "Allowed"
        case .notDetermined: "Grant"
        case .denied, .unknown: "Open Settings"
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                appState.setLaunchAtLogin(newValue)
                launchAtLogin = appState.launchAtLoginManager.isEnabled
            }
        )
    }

    private var sendEnterBinding: Binding<Bool> {
        Binding(
            get: { sendEnterAfterDictation },
            set: { newValue in
                appState.setSendEnterAfterDictation(newValue)
                sendEnterAfterDictation = appState.settings.sendEnterAfterDictation
            }
        )
    }

    private var liveTypingBinding: Binding<Bool> {
        Binding(
            get: { liveTyping },
            set: { newValue in
                appState.setLiveTyping(newValue)
                liveTyping = appState.settings.liveTyping
            }
        )
    }

    private var streamingLatencyBinding: Binding<Int> {
        Binding(
            get: { streamingLatencyMs },
            set: { newValue in
                appState.setStreamingLatencyMs(newValue)
                streamingLatencyMs = appState.settings.streamingLatencyMs
            }
        )
    }

    private var dictationLanguageBinding: Binding<String> {
        Binding(
            get: { dictationLanguage },
            set: { newValue in
                appState.setDictationLanguage(newValue)
                dictationLanguage = appState.settings.dictationLanguage
            }
        )
    }

}

// MARK: - Dictation test

private struct DictationTestView: View {
    @ObservedObject var appState: AppState
    @State private var testPasteText = ""
    @FocusState private var isTestPasteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus this box and dictate to preview output without pasting elsewhere.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextEditor(text: $testPasteText)
                .font(.body)
                .focused($isTestPasteFocused)
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isTestPasteFocused ? MUKTheme.accent.opacity(0.5) : .white.opacity(0.08)))
        }
        .frame(maxWidth: .infinity)
        .onDisappear {
            appState.setDictationTestActive(false)
        }
        .onChange(of: isTestPasteFocused) { _, focused in
            appState.setDictationTestActive(focused)
        }
        .onChange(of: appState.latestDictation?.id) {
            showLatestDictationInTestBox()
        }
    }

    private func showLatestDictationInTestBox() {
        guard let latestDictation = appState.latestDictation else { return }
        testPasteText = latestDictation.text
    }
}
