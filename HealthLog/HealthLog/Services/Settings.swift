import Foundation

enum SettingsKeys {
    static let waterGoal = "waterGoalGlasses"
    static let trackPeriod = "trackPeriod"
    static let customSymptoms = "customSymptoms"
    static let reminderEnabled = "dailyReminderEnabled"
    static let reminderTime = "dailyReminderTime" // seconds since midnight
    static let lockEnabled = "faceIDLockEnabled"

    static let defaultWaterGoal = 8
    static let defaultReminderTime = 21 * 3600.0 // 9pm

    static func parseList(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
