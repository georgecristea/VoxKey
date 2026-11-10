import Foundation
import MacUtilityKit

final class AppSettings: ObservableObject {
    @Published private(set) var selectedModelID: String
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var sendEnterAfterDictation: Bool
    /// Insert transcribed text into the focused app live while dictating (vs. paste on release).
    @Published private(set) var liveTyping: Bool
    /// Live-preview streaming chunk size in milliseconds (160 = snappiest, 320 = balanced, 1280 = steadiest).
    @Published private(set) var streamingLatencyMs: Int
    /// Spoken-language code for multilingual models ("auto" = detect, "en", "sv", …).
    @Published private(set) var dictationLanguage: String
    /// When true, the dictation hotkey is inert (service paused) until resumed.
    @Published private(set) var dictationPaused: Bool
    /// True once the user has been through first-run setup (model auto-pick + onboarding).
    @Published private(set) var hasCompletedSetup: Bool
    /// The push-to-talk hotkey binding.
    @Published private(set) var hotkey: MUKHotkey

    private enum Key {
        static let selectedModelID = "selectedModelID"
        static let launchAtLogin = "launchAtLogin"
        static let sendEnterAfterDictation = "sendEnterAfterDictation"
        static let liveTyping = "liveTyping"
        static let streamingLatencyMs = "streamingLatencyMs"
        static let dictationLanguage = "dictationLanguage"
        static let dictationPaused = "dictationPaused"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let hotkey = "hotkeyBinding"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.selectedModelID: SpeechModel.defaultID,
            Key.launchAtLogin: false,
            Key.sendEnterAfterDictation: false,
            Key.liveTyping: false,
            Key.streamingLatencyMs: 320,
            Key.dictationLanguage: DictationLanguage.defaultCode,
            Key.dictationPaused: false,
            Key.hasCompletedSetup: false
        ])
        selectedModelID = defaults.string(forKey: Key.selectedModelID) ?? SpeechModel.defaultID
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        sendEnterAfterDictation = defaults.bool(forKey: Key.sendEnterAfterDictation)
        liveTyping = defaults.bool(forKey: Key.liveTyping)
        streamingLatencyMs = defaults.integer(forKey: Key.streamingLatencyMs)
        dictationLanguage = defaults.string(forKey: Key.dictationLanguage) ?? DictationLanguage.defaultCode
        dictationPaused = defaults.bool(forKey: Key.dictationPaused)
        hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup)
        if let data = defaults.data(forKey: Key.hotkey),
            let decoded = try? JSONDecoder().decode(MUKHotkey.self, from: data)
        {
            hotkey = decoded
        } else {
            hotkey = .fnControl
        }
    }

    func setHotkey(_ hotkey: MUKHotkey) {
        self.hotkey = hotkey
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: Key.hotkey)
        }
    }

    func setSelectedModelID(_ id: String) {
        selectedModelID = id
        defaults.set(id, forKey: Key.selectedModelID)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        defaults.set(enabled, forKey: Key.launchAtLogin)
    }

    func setSendEnterAfterDictation(_ enabled: Bool) {
        sendEnterAfterDictation = enabled
        defaults.set(enabled, forKey: Key.sendEnterAfterDictation)
    }

    func setLiveTyping(_ enabled: Bool) {
        liveTyping = enabled
        defaults.set(enabled, forKey: Key.liveTyping)
    }

    func setStreamingLatencyMs(_ value: Int) {
        streamingLatencyMs = value
        defaults.set(value, forKey: Key.streamingLatencyMs)
    }

    func setDictationLanguage(_ code: String) {
        dictationLanguage = code
        defaults.set(code, forKey: Key.dictationLanguage)
    }

    func setDictationPaused(_ paused: Bool) {
        dictationPaused = paused
        defaults.set(paused, forKey: Key.dictationPaused)
    }

    func setHasCompletedSetup(_ completed: Bool) {
        hasCompletedSetup = completed
        defaults.set(completed, forKey: Key.hasCompletedSetup)
    }
}
