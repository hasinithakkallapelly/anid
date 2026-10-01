import Foundation

struct GeminiUploadedFile {
    let name: String
    let uri: String
    let mimeType: String
    let expiresAt: Date?
}

enum GeminiFilesServiceError: LocalizedError {
    case missingUploadURL
    case uploadFailed(String)
    case processingFailed
    case processingTimedOut

    var errorDescription: String? {
        switch self {
        case .missingUploadURL:
            return "Gemini didn't return an upload URL for the video."
        case .uploadFailed(let detail):
            return "Uploading the video to Gemini failed: \(detail)"
        case .processingFailed:
            return "Gemini failed to process the uploaded video."
        case .processingTimedOut:
            return "Gemini is still processing the video after a minute — try again shortly."
        }
    }
}

/// Uploads a video to the Gemini Files API so it can be referenced from a
/// generateContent request instead of inlined as base64 — videos are too
/// large to send inline reliably. This is Google's standard two-step
/// resumable upload protocol (start a session, then PUT the bytes), used
/// here as a single-shot upload since reel-sized videos comfortably fit in
/// one request.
enum GeminiFilesService {
    private static let uploadEndpoint = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files")!

    static func upload(fileURL: URL, mimeType: String, apiKey: String) async throws -> GeminiUploadedFile {
        let data = try Data(contentsOf: fileURL)

        var startRequest = URLRequest(url: uploadEndpoint)
        startRequest.httpMethod = "POST"
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["displayName": "anid-idea-video"]])

        let (_, startResponse) = try await URLSession.shared.data(for: startRequest)
        guard let httpStartResponse = startResponse as? HTTPURLResponse,
              let uploadURLString = httpStartResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiFilesServiceError.missingUploadURL
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, from: data)
        guard let httpUploadResponse = uploadResponse as? HTTPURLResponse,
              (200..<300).contains(httpUploadResponse.statusCode) else {
            let body = String(data: uploadData, encoding: .utf8) ?? ""
            throw GeminiFilesServiceError.uploadFailed(body)
        }

        var file = try decodeFile(from: uploadData)
        var attempts = 0
        while file.state == "PROCESSING", attempts < 30 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            file = try await fetchFile(name: file.name, apiKey: apiKey)
            attempts += 1
        }

        if file.state == "FAILED" {
            throw GeminiFilesServiceError.processingFailed
        }
        if file.state == "PROCESSING" {
            throw GeminiFilesServiceError.processingTimedOut
        }

        return GeminiUploadedFile(name: file.name, uri: file.uri, mimeType: mimeType, expiresAt: file.expirationDate)
    }

    private static func fetchFile(name: String, apiKey: String) async throws -> FileStatus {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name)")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try decodeFileStatus(from: data)
    }

    private static func decodeFile(from data: Data) throws -> FileStatus {
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        return decoded.file
    }

    private static func decodeFileStatus(from data: Data) throws -> FileStatus {
        try JSONDecoder().decode(FileStatus.self, from: data)
    }

    private struct UploadResponse: Decodable {
        let file: FileStatus
    }

    private struct FileStatus: Decodable {
        let name: String
        let uri: String
        let state: String
        let expirationTime: String?

        private enum CodingKeys: String, CodingKey {
            case name, uri, state, expirationTime
        }

        var expirationDate: Date? {
            expirationTime.flatMap { ISO8601DateFormatter().date(from: $0) }
        }
    }
}
