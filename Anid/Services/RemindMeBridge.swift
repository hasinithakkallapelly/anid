import Foundation
import UIKit

/// Hands a batch of todo items off to the Remind Me app via a custom URL
/// scheme. Remind Me isn't a server — it's a second, independent app on the
/// same device with its own local SwiftData store — so the payload rides in
/// the URL itself instead of through any shared backend.
///
/// This assumes Remind Me has been extended to handle
/// `remindme://importReminders?payload=<base64 JSON>`. That patch is
/// documented in Docs/RemindMeIntegration.md but hasn't been applied to the
/// remind-me repo yet — until it is, `send(_:)` will fail with
/// `.remindMeNotInstalled` even if Remind Me is on the device.
enum RemindMeBridge {
    private static let scheme = "remindme"

    private struct ExportItem: Encodable {
        let text: String
        let dueDate: String?
        let placeName: String?
    }

    static var isRemindMeInstalled: Bool {
        guard let url = URL(string: "\(scheme)://ping") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func send(_ items: [TodoItem]) async throws {
        guard !items.isEmpty else { return }

        let isoFormatter = ISO8601DateFormatter()
        let payload = items.map { item in
            ExportItem(
                text: item.text,
                dueDate: item.dueDate.map { isoFormatter.string(from: $0) },
                placeName: item.placeName
            )
        }
        let jsonData = try JSONEncoder().encode(payload)
        let base64 = jsonData.base64EncodedString()

        var components = URLComponents()
        components.scheme = scheme
        components.host = "importReminders"
        components.queryItems = [URLQueryItem(name: "payload", value: base64)]

        guard let url = components.url else {
            throw RemindMeBridgeError.encodingFailed
        }

        let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
        }
        if !opened {
            throw RemindMeBridgeError.remindMeNotInstalled
        }
    }
}

enum RemindMeBridgeError: LocalizedError {
    case encodingFailed
    case remindMeNotInstalled

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Couldn't build a link to Remind Me."
        case .remindMeNotInstalled:
            return "Remind Me didn't open this link. Make sure it's installed and has the import link support described in Docs/RemindMeIntegration.md."
        }
    }
}
