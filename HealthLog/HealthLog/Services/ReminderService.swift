import Foundation
import UserNotifications

/// One local "log your day" notification, repeating daily. Nothing leaves the
/// phone — this is scheduled by iOS itself.
enum ReminderService {
    private static let identifier = "daily-health-log"

    /// Returns false if the user declined notification permission.
    static func schedule(secondsSinceMidnight: Double) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "How was today?"
        content.body = "Take 30 seconds to log water, symptoms, and food."
        content.sound = .default

        var components = DateComponents()
        components.hour = Int(secondsSinceMidnight) / 3600
        components.minute = (Int(secondsSinceMidnight) % 3600) / 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
