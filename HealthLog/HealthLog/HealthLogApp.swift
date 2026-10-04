import SwiftUI
import SwiftData

@main
struct HealthLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // Stored only on this phone (in the app's own container). No server,
        // no sync, no network calls anywhere in the app.
        .modelContainer(for: [DayLog.self, LogEvent.self])
    }
}

/// Tabs, plus the optional Face ID lock from Settings.
struct RootView: View {
    @AppStorage(SettingsKeys.lockEnabled) private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    /// Only auto-prompt after coming back from the background. The Face ID
    /// sheet itself makes the app briefly inactive, so prompting on every
    /// "became active" would loop forever after a cancel.
    @State private var promptOnNextActive = true

    var body: some View {
        ZStack {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "heart.text.square") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "calendar") }
                TrendsView()
                    .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            }

            // Also covers the app-switcher snapshot while backgrounded.
            if lockEnabled && (!isUnlocked || scenePhase != .active) {
                LockScreen(unlock: unlock)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                isUnlocked = false
                promptOnNextActive = true
            }
            if phase == .active && lockEnabled && promptOnNextActive {
                promptOnNextActive = false
                unlock()
            }
        }
        .task {
            if lockEnabled && promptOnNextActive {
                promptOnNextActive = false
                unlock()
            }
        }
    }

    private func unlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            isUnlocked = await AppLock.authenticate()
            isAuthenticating = false
        }
    }
}

private struct LockScreen: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                Text("Health Log is locked")
                    .font(.headline)
                Button("Unlock", action: unlock)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [DayLog.self, LogEvent.self], inMemory: true)
}
