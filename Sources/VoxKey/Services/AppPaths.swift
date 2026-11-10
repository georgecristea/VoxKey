import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        get throws {
            guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw VoxKeyError.storage("Could not locate Application Support.")
            }
            let url = baseURL.appendingPathComponent("VoxKey", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    static var modelsDirectory: URL {
        get throws {
            var url = try supportDirectory.appendingPathComponent("Models", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            // Models are re-downloadable; keep them out of Time Machine backups.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            return url
        }
    }

}

enum VoxKeyError: LocalizedError {
    case storage(String)
    case microphoneUnavailable
    case recordingFailed(String)
    case transcriberUnavailable(String)
    case pastePermissionMissing

    var errorDescription: String? {
        switch self {
        case .storage(let message): message
        case .microphoneUnavailable: "Microphone permission is required."
        case .recordingFailed(let message): message
        case .transcriberUnavailable(let message): message
        case .pastePermissionMissing: "Accessibility permission is required to paste."
        }
    }
}
