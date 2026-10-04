import Foundation

/// Simple "worse on days with X" comparisons. This is counting, not
/// statistics — it can't separate cause from coincidence, so every result is
/// shown as a hint to test (e.g. cut that food for two weeks), never as proof.
struct Pattern: Identifiable {
    let id = UUID()
    let title: String
    let symptomArea: String
    let withAverage: Double
    let withoutAverage: Double
    let withDays: Int
    let withoutDays: Int

    var difference: Double { withAverage - withoutAverage }
}

enum Patterns {
    /// Below this many days on each side, a comparison is mostly noise.
    static let minimumDays = 3
    /// Only show differences at least this big (on the 0–5 severity scale).
    static let minimumDifference = 0.5

    static func find(in summaries: [DaySummary], waterGoal: Int) -> [Pattern] {
        let calendar = Calendar.current
        let byDay = Dictionary(uniqueKeysWithValues: summaries.map { ($0.day, $0) })

        /// Worst severity that day or the next (symptoms often lag a trigger
        /// by hours), using only the same day if the next wasn't logged.
        func outcome(_ summary: DaySummary, _ value: (DaySummary) -> Int) -> Double {
            var worst = value(summary)
            if let next = calendar.date(byAdding: .day, value: 1, to: summary.day), let nextSummary = byDay[next] {
                worst = max(worst, value(nextSummary))
            }
            return Double(worst)
        }

        func compare(
            _ title: String,
            area: String,
            pool: [DaySummary],
            isExposed: (DaySummary) -> Bool,
            value: (DaySummary) -> Int
        ) -> Pattern? {
            let exposed = pool.filter(isExposed)
            let unexposed = pool.filter { !isExposed($0) }
            guard exposed.count >= minimumDays, unexposed.count >= minimumDays else { return nil }
            let withAvg = exposed.map { outcome($0, value) }.reduce(0, +) / Double(exposed.count)
            let withoutAvg = unexposed.map { outcome($0, value) }.reduce(0, +) / Double(unexposed.count)
            let pattern = Pattern(
                title: title,
                symptomArea: area,
                withAverage: withAvg,
                withoutAverage: withoutAvg,
                withDays: exposed.count,
                withoutDays: unexposed.count
            )
            return pattern.difference >= minimumDifference ? pattern : nil
        }

        var results: [Pattern] = []

        // Food tags vs gut and bladder symptoms, only among days where food
        // was actually logged (otherwise "no dairy" might just mean "forgot").
        let foodDays = summaries.filter(\.loggedFood)
        for tag in Catalog.foodTags {
            if let p = compare(tag, area: "Gut", pool: foodDays, isExposed: { $0.foodTags.contains(tag) }, value: \.gutMax) {
                results.append(p)
            }
            if let p = compare(tag, area: "Urinary", pool: foodDays, isExposed: { $0.foodTags.contains(tag) }, value: \.urinaryMax) {
                results.append(p)
            }
        }

        // Low water vs urinary symptoms.
        let waterDays = summaries.filter { $0.water > 0 }
        if let p = compare("Under \(waterGoal) glasses of water", area: "Urinary", pool: waterDays, isExposed: { $0.water < waterGoal }, value: \.urinaryMax) {
            results.append(p)
        }

        // High stress vs gut symptoms.
        let stressDays = summaries.filter { $0.stress != nil }
        if let p = compare("Stress 4–5", area: "Gut", pool: stressDays, isExposed: { ($0.stress ?? 0) >= 4 }, value: \.gutMax) {
            results.append(p)
        }

        // Short sleep vs gut symptoms.
        let sleepDays = summaries.filter { $0.sleepHours != nil }
        if let p = compare("Under 6h sleep", area: "Gut", pool: sleepDays, isExposed: { ($0.sleepHours ?? 0) < 6 }, value: \.gutMax) {
            results.append(p)
        }

        return results.sorted { $0.difference > $1.difference }
    }
}
