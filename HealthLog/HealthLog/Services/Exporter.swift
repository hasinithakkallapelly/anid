import Foundation

/// Builds the doctor summary and CSV files for a date range.
enum Exporter {
    struct Output {
        let summary: String
        let files: [URL]
    }

    static func make(from start: Date, to end: Date, events allEvents: [LogEvent], dayLogs allDayLogs: [DayLog], waterGoal: Int) throws -> Output {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end

        let events = allEvents
            .filter { $0.timestamp >= startDay && $0.timestamp < endExclusive }
            .sorted { $0.timestamp < $1.timestamp }
        let dayLogs = allDayLogs
            .filter { $0.day >= startDay && $0.day < endExclusive }
            .sorted { $0.day < $1.day }
        let summaries = DaySummary.build(events: events, dayLogs: dayLogs).sorted { $0.day < $1.day }

        let summary = summaryText(start: startDay, end: end, events: events, summaries: summaries, waterGoal: waterGoal)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HealthLogExport", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suffix = "\(DayKey.string(for: startDay))-to-\(DayKey.string(for: end))"

        let summaryURL = folder.appendingPathComponent("health-summary-\(suffix).txt")
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)

        let eventsURL = folder.appendingPathComponent("health-events-\(suffix).csv")
        try eventsCSV(events).write(to: eventsURL, atomically: true, encoding: .utf8)

        let dailyURL = folder.appendingPathComponent("health-daily-\(suffix).csv")
        try dailyCSV(dayLogs).write(to: dailyURL, atomically: true, encoding: .utf8)

        return Output(summary: summary, files: [summaryURL, eventsURL, dailyURL])
    }

    // MARK: - Summary

    private static func summaryText(start: Date, end: Date, events: [LogEvent], summaries: [DaySummary], waterGoal: Int) -> String {
        let dateStyle = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        let shortDate = Date.FormatStyle.dateTime.day().month(.abbreviated)
        let totalDays = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        var lines: [String] = []

        lines.append("HEALTH LOG SUMMARY")
        lines.append("\(start.formatted(dateStyle)) – \(end.formatted(dateStyle)) (\(totalDays) days, \(summaries.count) with entries)")
        lines.append("")

        let symptoms = events.filter { $0.kind == .symptom }

        func symptomBlock(_ heading: String, _ isInArea: (String) -> Bool) {
            let areaSymptoms = symptoms.filter { isInArea($0.title) }
            let days = Set(areaSymptoms.map { Calendar.current.startOfDay(for: $0.timestamp) })
            lines.append(heading)
            lines.append("- Days with symptoms: \(days.count)")
            if !areaSymptoms.isEmpty {
                lines.append("- Most common: " + countList(areaSymptoms.map(\.title)))
                let severe = areaSymptoms.filter { ($0.severity ?? 0) >= 4 }
                if !severe.isEmpty {
                    let severeDays = Set(severe.map { Calendar.current.startOfDay(for: $0.timestamp) }).sorted()
                    lines.append("- Bad/severe (4–5) on: " + severeDays.map { $0.formatted(shortDate) }.joined(separator: ", "))
                }
            }
        }

        symptomBlock("URINARY", Catalog.isUrinary)
        let redFlags = symptoms.filter(\.isRedFlag)
        if !redFlags.isEmpty {
            lines.append("- Red-flag symptoms: " + redFlags.map { "\($0.title) (\($0.timestamp.formatted(shortDate)))" }.joined(separator: "; "))
        }
        let peeDays = summaries.filter { $0.urinations > 0 }
        if !peeDays.isEmpty {
            lines.append("- Avg times peed per day: \(average(peeDays.map { Double($0.urinations) })) (on \(peeDays.count) days counted)")
        }
        let waterDays = summaries.filter { $0.water > 0 }
        if !waterDays.isEmpty {
            lines.append("- Avg water: \(average(waterDays.map { Double($0.water) })) glasses/day (goal \(waterGoal))")
        }
        lines.append("")

        symptomBlock("GUT", Catalog.isGut)
        let poops = events.filter { $0.kind == .bowel }
        if !poops.isEmpty {
            let types = poops.compactMap(\.bristol)
            let hard = types.filter { $0 <= 2 }.count
            let normal = types.filter { (3...4).contains($0) }.count
            let loose = types.filter { $0 >= 5 }.count
            let days = Set(poops.map { Calendar.current.startOfDay(for: $0.timestamp) }).count
            lines.append("- Bowel movements: \(poops.count) over \(days) days")
            lines.append("- Bristol type: 1–2 (hard) \(hard), 3–4 (normal) \(normal), 5–7 (loose) \(loose)")
            let flags = poops.flatMap(\.tags)
            if !flags.isEmpty { lines.append("- Also noted: " + countList(flags)) }
            let bloody = poops.filter { $0.tags.contains(Catalog.bloodFlag) }
            if !bloody.isEmpty {
                lines.append("- Blood noted on: " + bloody.map { $0.timestamp.formatted(shortDate) }.joined(separator: ", "))
            }
        }
        lines.append("")

        let otherSymptoms = symptoms.filter { !Catalog.isUrinary($0.title) && !Catalog.isGut($0.title) }
        if !otherSymptoms.isEmpty {
            lines.append("OTHER SYMPTOMS")
            lines.append("- " + countList(otherSymptoms.map(\.title)))
            lines.append("")
        }

        let meds = events.filter { $0.kind == .medication }
        if !meds.isEmpty {
            lines.append("MEDICINES")
            let grouped = Dictionary(grouping: meds) { $0.detail.isEmpty ? $0.title : "\($0.title) \($0.detail)" }
            for (name, doses) in grouped.sorted(by: { $0.key < $1.key }) {
                let first = doses.map(\.timestamp).min()!
                let last = doses.map(\.timestamp).max()!
                lines.append("- \(name): \(doses.count)× (\(first.formatted(shortDate)) – \(last.formatted(shortDate)))")
            }
            lines.append("")
        }

        let periodDays = summaries.filter(\.onPeriod)
        let stressDays = summaries.compactMap(\.stress)
        let sleepDays = summaries.compactMap(\.sleepHours)
        if !periodDays.isEmpty || !stressDays.isEmpty || !sleepDays.isEmpty {
            lines.append("GENERAL")
            if !periodDays.isEmpty {
                lines.append("- Period days: " + periodDays.map { $0.day.formatted(shortDate) }.joined(separator: ", "))
            }
            if !sleepDays.isEmpty { lines.append("- Avg sleep: \(average(sleepDays)) h") }
            if !stressDays.isEmpty { lines.append("- Avg stress: \(average(stressDays.map { Double($0) }))/5") }
            lines.append("")
        }

        let patterns = Patterns.find(in: summaries, waterGoal: waterGoal)
        if !patterns.isEmpty {
            lines.append("POSSIBLE PATTERNS (self-tracked, not tested)")
            for p in patterns.prefix(5) {
                lines.append("- \(p.symptomArea) symptoms worse with \(p.title): avg \(average([p.withAverage])) vs \(average([p.withoutAverage])) (\(p.withDays) vs \(p.withoutDays) days)")
            }
            lines.append("")
        }

        let foods = events.filter { $0.kind == .food }
        if !foods.isEmpty {
            lines.append("FOOD DIARY")
            let byDay = Dictionary(grouping: foods) { Calendar.current.startOfDay(for: $0.timestamp) }
            for (day, items) in byDay.sorted(by: { $0.key < $1.key }) {
                lines.append(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                for food in items.sorted(by: { $0.timestamp < $1.timestamp }) {
                    var line = "  \(timeFormatter.string(from: food.timestamp))"
                    if let meal = food.meal { line += " \(meal.label):" }
                    line += " \(food.title)"
                    if !food.tags.isEmpty { line += " [\(food.tags.joined(separator: ", "))]" }
                    lines.append(line)
                }
            }
            lines.append("")
        }

        lines.append("Full detail in the attached CSV files.")
        return lines.joined(separator: "\n")
    }

    private static func countList(_ items: [String]) -> String {
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
    }

    private static func average(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "—" }
        return (values.reduce(0, +) / Double(values.count)).formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: - CSV

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func eventsCSV(_ events: [LogEvent]) -> String {
        var rows = [["date", "time", "type", "meal", "item", "severity_1to5", "bristol_type", "tags", "details"]]
        for event in events {
            rows.append([
                DayKey.string(for: event.timestamp),
                timeFormatter.string(from: event.timestamp),
                event.kind.rawValue,
                event.meal?.rawValue ?? "",
                event.title,
                event.severity.map(String.init) ?? "",
                event.bristol.map(String.init) ?? "",
                event.tags.joined(separator: "; "),
                event.detail,
            ])
        }
        return csv(rows)
    }

    private static func dailyCSV(_ dayLogs: [DayLog]) -> String {
        var rows = [["date", "water_glasses", "times_peed", "sleep_hours", "stress_1to5", "feeling_1to5", "on_period", "notes"]]
        for log in dayLogs {
            rows.append([
                log.dayKey,
                String(log.waterGlasses),
                String(log.urinations),
                log.sleepHours.map { String($0) } ?? "",
                log.stress.map(String.init) ?? "",
                log.feeling.map(String.init) ?? "",
                log.onPeriod ? "yes" : "",
                log.notes,
            ])
        }
        return csv(rows)
    }

    private static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }
            .joined(separator: ",")
        }
        .joined(separator: "\n") + "\n"
    }
}
