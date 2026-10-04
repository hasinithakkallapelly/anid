import Foundation
import SwiftData

/// The once-a-day numbers: water, how often you peed, sleep, stress, overall
/// feeling. Created lazily the first time you change something for that day,
/// so browsing past days doesn't fill history with empty entries.
@Model
final class DayLog {
    /// "yyyy-MM-dd" in the calendar's current time zone. Used as the key
    /// instead of a Date so a time-zone change can't split one day into two.
    @Attribute(.unique) var dayKey: String
    var day: Date
    var waterGlasses: Int
    var urinations: Int
    var sleepHours: Double?
    /// 1 (calm) ... 5 (very stressed)
    var stress: Int?
    /// 1 (awful) ... 5 (great)
    var feeling: Int?
    var onPeriod: Bool
    var notes: String

    init(day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        self.dayKey = DayKey.string(for: start)
        self.day = start
        self.waterGlasses = 0
        self.urinations = 0
        self.sleepHours = nil
        self.stress = nil
        self.feeling = nil
        self.onPeriod = false
        self.notes = ""
    }

    static func fetch(for date: Date, in context: ModelContext) -> DayLog? {
        let key = DayKey.string(for: date)
        var descriptor = FetchDescriptor<DayLog>(predicate: #Predicate<DayLog> { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func fetchOrCreate(for date: Date, in context: ModelContext) -> DayLog {
        if let existing = fetch(for: date, in: context) { return existing }
        let log = DayLog(day: date)
        context.insert(log)
        return log
    }
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(for date: Date) -> String {
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.timeZone = .current
        return formatter.date(from: key)
    }
}
