import Foundation

/// One day's events and daily numbers boiled down, for History, Trends and
/// the export. Plain values, not SwiftData models.
struct DaySummary: Identifiable {
    let day: Date
    var water = 0
    var urinations = 0
    var sleepHours: Double?
    var stress: Int?
    var feeling: Int?
    var onPeriod = false
    /// Worst urinary / gut symptom severity that day, 0 if none.
    var urinaryMax = 0
    var gutMax = 0
    var bristolTypes: [Int] = []
    var foodTags: Set<String> = []
    var loggedFood = false
    var medications: [String] = []
    var symptomNames: [String] = []
    var hasRedFlag = false

    var id: Date { day }

    var topSymptoms: [String] {
        var counts: [String: Int] = [:]
        for name in symptomNames { counts[name, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }

    static func build(events: [LogEvent], dayLogs: [DayLog]) -> [DaySummary] {
        let calendar = Calendar.current
        var byDay: [Date: DaySummary] = [:]

        for log in dayLogs {
            let day = calendar.startOfDay(for: log.day)
            var summary = byDay[day] ?? DaySummary(day: day)
            summary.water = log.waterGlasses
            summary.urinations = log.urinations
            summary.sleepHours = log.sleepHours
            summary.stress = log.stress
            summary.feeling = log.feeling
            summary.onPeriod = log.onPeriod
            byDay[day] = summary
        }

        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            var summary = byDay[day] ?? DaySummary(day: day)
            switch event.kind {
            case .symptom:
                summary.symptomNames.append(event.title)
                let severity = event.severity ?? 0
                if Catalog.isUrinary(event.title) { summary.urinaryMax = max(summary.urinaryMax, severity) }
                if Catalog.isGut(event.title) { summary.gutMax = max(summary.gutMax, severity) }
            case .bowel:
                if let bristol = event.bristol { summary.bristolTypes.append(bristol) }
            case .food:
                summary.loggedFood = true
                summary.foodTags.formUnion(event.tags)
            case .medication:
                summary.medications.append(event.title)
            case .note:
                break
            }
            if event.isRedFlag { summary.hasRedFlag = true }
            byDay[day] = summary
        }

        return Array(byDay.values)
    }
}
