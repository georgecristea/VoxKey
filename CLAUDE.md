# VoxKey

VoxKey is a macOS menu bar **push-to-talk voice dictation** app. Hold a global hotkey (default
**Fn+Control**), speak, release — the audio is transcribed **on-device** and pasted into the
frontmost app at the cursor. No audio leaves the Mac, and nothing is written to disk except
settings and downloaded models.

## Architecture

SwiftUI + AppKit menu bar app (`LSUIElement`, no Dock icon). Pure Swift, no Python.

```
Sources/VoxKey/
  App/         AppDelegate, AppState (central ObservableObject), AppSettings, VoxKeyMain
  Services/    DictationStreamer (mic tap + live preview), TranscriptionCoordinator (engine routing),
               TranscriptionEngine (protocol), FluidAudioEngine (Parakeet, Neural Engine),
               WhisperCppEngine (whisper.cpp, Metal/CPU), HardwareRecommender, PasteInjector, AppPaths
  UI/          StatusBarController, MainPopoverView, SettingsView, OnboardingWindowController, AboutView
  Models/      SpeechModel (catalog + ModelRuntimeStatus), DictationLanguage
```

- **AppState** orchestrates everything: capture lifecycle, transcription, permissions, model
  select/download, metering. UI observes it. The hotkey is a `MUKHotkeyEngine` (down →
  begin capture, up → end capture).
- **DictationStreamer** taps the mic with AVAudioEngine, resamples to 16 kHz mono in memory, and
  feeds the streaming Parakeet EOU 120M model for the live preview (Apple Silicon only). On release
  the full buffer goes to the selected model through **TranscriptionCoordinator**.
- **StatusBarController** owns the `NSStatusItem` + a single `.transient` `NSPopover` hosting
  `MainPopoverView`. Settings and About are **in-popover screens**, not separate windows.
- **PasteInjector** synthesizes ⌘V via `CGEvent` (requires Accessibility) and restores the previous
  clipboard; "Type as I speak" types live with CGEvents instead.
- **HardwareRecommender** picks the first-run model: Whisper Base on Intel, Parakeet v2 for
  English-only users on Apple Silicon, Parakeet v3 otherwise.

## Shared package: MacUtilityKit

VoxKey depends on **MacUtilityKit** (github.com/georgecristea/MacUtilityKit), a shared macOS
toolkit (theme, popover shell, components, hotkeys, permissions, onboarding, launch-at-login).
**Rule: any UI or behavior that other apps could reuse goes into MacUtilityKit**, not VoxKey. To
change both together: `swift package edit MacUtilityKit --path ../MacUtilityKit`
(`swift package unedit MacUtilityKit` to go back); ship by tagging MacUtilityKit and bumping
`Package.resolved` here. The host app sets `MUKTheme.brand` once at launch (`AppDelegate`).

## Build & run

```sh
swift build -c release          # build
swift run                       # build + launch (dev only)
./scripts/install.sh            # package, install to /Applications, relaunch — use after every change
```

`package-app.sh` embeds the whisper.cpp `whisper.framework` (a binary target) in
`Contents/lib`. Models download on demand to `~/Library/Application Support/VoxKey/Models/`.

## Permissions

Needs **Microphone** (recording) and **Accessibility** (global hotkey + paste). Granted via
Settings/onboarding. Deep-link: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
Bundle id `com.georgecristea.VoxKey`. To test a cold-start grant flow:
`tccutil reset All com.georgecristea.VoxKey` (quit the app first), then relaunch.

> TCC keys Accessibility to the code-signing identity — ad-hoc/dev re-signing on each rebuild
> invalidates the grant ("granted-but-stale"). Stable Developer ID signing is the fix.

## Verifying a change

After a change, `swift build` and run the app: open the popover from the menu bar, hold the hotkey,
speak, release, confirm paste. For UI work, also check the popover dismisses on click-away and
Settings/About navigate in place.
