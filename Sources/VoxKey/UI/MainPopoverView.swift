import MacUtilityKit
import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var appState: AppState
    @State private var screen: Screen = .main

    enum Screen { case main, settings, about }

    var body: some View {
        MUKPopoverShell(message: appState.lastMessage) {
            header
        } content: {
            content
        }
    }

    @ViewBuilder private var header: some View {
        switch screen {
        case .main:
            MUKHeader(
                title: "VoxKey",
                subtitle: appState.dictationPaused ? "Dictation paused" : appState.selectedModel.displayName,
                systemImage: "waveform")
            {
                MUKIconButton(
                    systemImage: appState.dictationPaused ? "play.circle.fill" : "pause.circle",
                    help: appState.dictationPaused ? "Resume dictation" : "Pause dictation")
                {
                    appState.setDictationPaused(!appState.dictationPaused)
                }
                MUKIconButton(systemImage: "gearshape", help: "Settings") {
                    navigate(to: .settings)
                }
                MUKIconButton(systemImage: "power", help: "Quit VoxKey") {
                    appState.quit()
                }
            }
        case .settings:
            MUKBackHeader(title: "Settings", onBack: { navigate(to: .main) })
        case .about:
            MUKBackHeader(title: "About", onBack: { navigate(to: .settings) })
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .main:
            MainScreen(appState: appState)
        case .settings:
            SettingsView(appState: appState, onShowAbout: { navigate(to: .about) })
        case .about:
            AboutView()
        }
    }

    private func navigate(to screen: Screen) {
        withAnimation(.easeInOut(duration: 0.18)) { self.screen = screen }
    }
}

// MARK: - Main screen

private struct MainScreen: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HeroCaptureView(appState: appState)
                StatusStripView(appState: appState)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().opacity(0.5)

            ModelsSectionView(appState: appState)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Hero capture (compact)

private struct HeroCaptureView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        MUKCard(padding: 14) {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(panelColor.opacity(0.12))
                        .frame(width: 60, height: 60)
                    Circle()
                        .strokeBorder(panelColor.opacity(0.28), lineWidth: 1.5)
                        .frame(width: 60, height: 60)

                    switch appState.captureState {
                    case .recording:
                        MUKLevelMeter(level: appState.inputLevel, barCount: 9, height: 32)
                            .frame(width: 46)
                    case .transcribing:
                        ProgressView()
                            .controlSize(.small)
                    default:
                        Image(systemName: panelIcon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(panelColor)
                    }
                }
                .frame(height: 60)

                Text(panelTitle)
                    .font(.subheadline.weight(.semibold))

                Group {
                    if appState.captureState == .recording {
                        Text(elapsedString)
                            .font(.system(.caption, design: .monospaced).weight(.medium))
                            .foregroundStyle(.red)
                    } else {
                        Text(panelSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(height: 14)

                if appState.captureState == .recording, !appState.partialText.isEmpty {
                    Text(appState.partialText)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }

                if appState.captureState == .recording {
                    Button(role: .cancel) {
                        appState.cancelCapture()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if isPaused {
                    Button {
                        appState.setDictationPaused(false)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    HotkeyHintView(label: appState.hotkeyLabel)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.18), value: appState.captureState)
            .animation(.easeInOut(duration: 0.18), value: appState.dictationPaused)
        }
    }

    private var isPaused: Bool {
        appState.dictationPaused && appState.captureState == .idle
    }

    private var elapsedString: String {
        let total = Int(appState.recordingElapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var panelTitle: String {
        if isPaused { return "Dictation paused" }
        return switch appState.captureState {
        case .idle: "Ready to dictate"
        case .recording: "Listening…"
        case .transcribing: "Transcribing on-device"
        case .pasted: "Pasted"
        case .error: "Check setup"
        }
    }

    private var panelSubtitle: String {
        if isPaused { return "Resume to start dictating again." }
        return switch appState.captureState {
        case .idle: "Hold the hotkey, speak, release to paste at your cursor."
        case .recording: ""
        case .transcribing: "Running locally — your audio never leaves this Mac."
        case .pasted: "Inserted at your cursor."
        case .error: "Open Settings to resolve the issue."
        }
    }

    private var panelIcon: String {
        if isPaused { return "pause.circle.fill" }
        return switch appState.captureState {
        case .idle: "mic.fill"
        case .recording: "waveform"
        case .transcribing: "waveform.and.magnifyingglass"
        case .pasted: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var panelColor: Color {
        if isPaused { return MUKTheme.warning }
        return switch appState.captureState {
        case .idle: MUKTheme.accent
        case .recording: .red
        case .transcribing: MUKTheme.accent
        case .pasted: .green
        case .error: .red
        }
    }
}

private struct HotkeyHintView: View {
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.tap")
                .font(.caption2)
            Text("Hold \(label)")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.45), in: Capsule())
    }
}

// MARK: - Status strip

private struct StatusStripView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            MUKStatusChip(label: "Mic", value: appState.microphonePermission.label, tone: appState.microphonePermission.tone)
            MUKStatusChip(label: "Paste", value: appState.accessibilityPermission.label, tone: appState.accessibilityPermission.tone)
            MUKStatusChip(
                label: "Engine",
                value: appState.dictationPaused ? "Paused" : (appState.engine.isRunning ? "Ready" : "Offline"),
                tone: appState.dictationPaused ? .warning : (appState.engine.isRunning ? .success : .warning))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Models

private struct ModelsSectionView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech models")
                        .font(.subheadline.weight(.semibold))
                    Text(appState.hardwareRationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.refreshModelStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh model status")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    engineSection("Parakeet · Neural Engine", engine: .parakeet)
                    engineSection(whisperSectionTitle, engine: .whisper)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    /// whisper.cpp uses Metal (GPU) on Apple Silicon and CPU on Intel.
    private var whisperSectionTitle: String {
        MUKHardware.current.isAppleSilicon ? "Whisper · GPU (verbatim)" : "Whisper · CPU (verbatim)"
    }

    /// One engine's models, ordered most-capable → lightest (top to bottom).
    @ViewBuilder
    private func engineSection(_ title: String, engine: SpeechEngineKind) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
        ForEach(SpeechModel.catalog.filter { $0.engine == engine }) { model in
            ModelRow(appState: appState, model: model)
        }
    }
}

private struct ModelRow: View {
    @ObservedObject var appState: AppState
    let model: SpeechModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(MUKTheme.accentGradient) : AnyShapeStyle(Color.secondary))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.callout.weight(.medium))
                        if isLoaded {
                            MUKBadge("Loaded", tone: .success)
                        } else if isSelected {
                            MUKBadge("Selected", tone: .neutral)
                        } else if isRecommended {
                            MUKBadge("Recommended", tone: .neutral)
                        }
                    }
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                controls
            }

            if isLoading {
                progressRow(label: "Loading into memory…", value: nil)
            } else if status == .downloading {
                progressRow(label: downloadLabel, value: downloadProgress)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: MUKTheme.rowRadius, style: .continuous)
                .fill(isSelected ? MUKTheme.accent.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: MUKTheme.rowRadius, style: .continuous)
                .strokeBorder(isSelected ? MUKTheme.accent.opacity(0.45) : .white.opacity(0.05), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    @ViewBuilder
    private func progressRow(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MUKProgressBar(value: value)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var controls: some View {
        if isLoading {
            EmptyView()
        } else {
            switch status {
            case .downloading:
                EmptyView()
            case .downloaded:
                HStack(spacing: 6) {
                    if !isSelected {
                        Button {
                            appState.selectModel(model)
                        } label: {
                            Text("Select")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            appState.deleteModel(model)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Delete model")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MUKTheme.accentGradient)
                    }
                }
            default:
                Button {
                    appState.downloadModel(model)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var isSelected: Bool { model.id == appState.engine.runtimeStatus.selectedModelID }
    private var isLoaded: Bool { model.id == appState.engine.runtimeStatus.loadedModelID }
    private var isRecommended: Bool { model.id == appState.recommendedModelID }
    private var isLoading: Bool { model.id == appState.loadingModelID }
    private var status: ModelAvailability { appState.engine.runtimeStatus.availability(for: model) }
    private var downloadProgress: Double? { appState.engine.runtimeStatus.downloadProgress[model.id] }

    private var downloadLabel: String {
        if let progress = downloadProgress {
            return "Downloading \(Int(progress * 100))%"
        }
        return "Downloading…"
    }

    private var detailText: String {
        "\(statusLabel) · \(model.downloadSizeLabel)"
    }

    private var statusLabel: String {
        if isLoading { return "Loading" }
        switch status {
        case .unknown: return "Checking"
        case .notDownloaded: return "Not downloaded"
        case .downloading: return "Downloading"
        case .downloaded: return "Ready"
        case .error: return "Error"
        }
    }

    private var iconName: String {
        switch model.tier {
        case .bestAccuracy: "star.circle.fill"
        case .fastHighQuality: "bolt.circle.fill"
        case .balanced: "dial.medium.fill"
        case .small: "leaf.circle.fill"
        }
    }
}
