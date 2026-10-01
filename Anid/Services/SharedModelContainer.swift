import Foundation
import SwiftData

/// Builds the SwiftData container both the main app and the Share
/// Extension use, backed by an App Group container instead of the app's
/// private Documents folder — the extension runs as a separate process and
/// can only reach app data that lives in a shared App Group, not the host
/// app's sandbox.
enum SharedModelContainer {
    static let appGroupID = "group.com.hasini.anid"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group container unavailable — check that \"\(appGroupID)\" is enabled under Signing & Capabilities for both the Anid and AnidShare targets.")
        }
        return url
    }

    static func make() -> ModelContainer {
        let schema = Schema([Idea.self, TodoItem.self, ChatMessage.self])
        let storeURL = containerURL.appendingPathComponent("Anid.sqlite")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create shared ModelContainer: \(error)")
        }
    }
}
