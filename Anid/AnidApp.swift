import SwiftUI
import SwiftData

@main
struct AnidApp: App {
    var sharedModelContainer: ModelContainer = SharedModelContainer.make()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
