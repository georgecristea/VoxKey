import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(appState: AppState, onDone: @escaping () -> Void) {
        let recommended = SpeechModel.model(for: appState.recommendedModelID) ?? SpeechModel.catalog[0]
        let requirements = [
            MUKPermissionRequirement(
                id: "microphone",
                title: "Microphone",
                detail: "So VoxKey can hear you while you hold the hotkey.",
                systemImage: "mic.fill",
                status: { MUKPermissions.microphone },
                request: { appState.requestMicrophonePermission() }),
            MUKPermissionRequirement(
                id: "accessibility",
                title: "Accessibility",
                detail: "Lets VoxKey paste transcribed text into any app.",
                systemImage: "cursorarrow.click",
                status: { MUKPermissions.accessibility },
                request: { appState.requestAccessibilityPermission() }),
            MUKPermissionRequirement(
                id: "model",
                title: "Speech model",
                detail: "Download \(recommended.displayName) (\(recommended.downloadSizeLabel)) to transcribe on-device.",
                systemImage: "waveform",
                actionTitle: "Download",
                status: {
                    appState.engine.runtimeStatus.availability(for: recommended) == .downloaded
                        ? .granted : .notDetermined
                },
                request: { appState.downloadModel(recommended) },
                isInProgress: {
                    appState.engine.runtimeStatus.availability(for: recommended) == .downloading
                }),
        ]
        let view = MUKOnboardingView(requirements: requirements, onDone: onDone)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to VoxKey"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}
