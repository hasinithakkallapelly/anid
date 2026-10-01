import Foundation

/// Persists a picked video into the app's own Documents folder, since a
/// PhotosPicker only hands us a temporary file that disappears once the
/// picker closes. Idea.localVideoFilename stores just the filename this
/// returns; resolve it back to a full path with `url(for:)` whenever it's
/// needed (uploading to Gemini, letting the user re-watch it, etc).
enum VideoStorage {
    private static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videos = documents.appendingPathComponent("Videos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: videos.path) {
            try? FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        }
        return videos
    }

    /// Copies a video from a temporary location (e.g. one handed back by
    /// PhotosPicker) into permanent app storage, returning the filename to
    /// store on the Idea.
    static func store(from temporaryURL: URL) throws -> String {
        let filename = "\(UUID().uuidString).\(temporaryURL.pathExtension)"
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        return filename
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func delete(filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    static func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        default: return "video/mp4"
        }
    }
}
