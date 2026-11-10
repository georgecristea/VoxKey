import Foundation

/// Curated spoken-language choices for the multilingual models (Parakeet v3, Whisper Large v3).
/// English-only models ignore this. "auto" lets the model detect the language (which can
/// mis-fire on short clips — hence English is the default).
enum DictationLanguage {
    static let defaultCode = "en"

    static let options: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("sv", "Swedish"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("uk", "Ukrainian"),
    ]

    static func name(for code: String) -> String {
        options.first { $0.code == code }?.name ?? code
    }
}
