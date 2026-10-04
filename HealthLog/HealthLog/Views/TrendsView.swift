import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query private var events: [LogEvent]
    @Query private var dayLogs: [DayLog]
    @AppStorage(SettingsKeys.waterGoal) private var waterGoal = SettingsKeys.defaultWaterGoal
    @State private var rangeDays = 30

    private var allSummaries: [DaySummary] {
        DaySummary.build(events: events, dayLogs: dayLogs).sorted { $0.day < $1.day }
    }

    private var rangeStart: Date {
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: -(rangeDays - 1), to: today) ?? today
    }

    var body: some View {
        NavigationStack {
            let summaries = allSummaries
            let inRange = summaries.filter { $0.day >= rangeStart }
            List {
                Picker("Range", selection: $rangeDays) {
                    Text("2 weeks").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section("Stats for this range") {
                    StatsGrid(summaries: inRange, waterGoal: waterGoal)
                }

                Section {
                    SymptomChart(summaries: inRange)
                        .frame(height: 200)
                } header: {
                    Text("Worst symptom per day")
                } footer: {
                    Text("0 = nothing logged, 5 = severe.")
                }

                Section("Poop type (Bristol)") {
                    BristolChart(summaries: inRange)
                        .frame(height: 200)
                }

                Section("Water") {
                    WaterChart(summaries: inRange, goal: waterGoal)
                        .frame(height: 180)
                }

                PatternsSection(patterns: Patterns.find(in: summaries, waterGoal: waterGoal))
            }
            .navigationTitle("Trends")
        }
    }
}

private struct StatsGrid: View {
    let summaries: [DaySummary]
    let waterGoal: Int

    var body: some View {
        let utiDays = summaries.filter { $0.urinaryMax > 0 }.count
        let gutDays = summaries.filter { $0.gutMax > 0 }.count
        let types = summaries.flatMap(\.bristolTypes)
        let normal = types.filter { (3...4).contains($0) }.count
        let waterDays = summaries.filter { $0.water > 0 }
        let avgWater = waterDays.isEmpty ? nil : Double(waterDays.map(\.water).reduce(0, +)) / Double(waterDays.count)

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Days with urinary symptoms")
                Text("\(utiDays)").bold()
            }
            GridRow {
                Text("Days with gut symptoms")
                Text("\(gutDays)").bold()
            }
            GridRow {
                Text("Poops logged / normal (3–4)")
                Text(types.isEmpty ? "—" : "\(types.count) / \(normal)").bold()
            }
            GridRow {
                Text("Average water")
                Text(avgWater.map { "\($0.formatted(.number.precision(.fractionLength(1)))) / \(waterGoal)" } ?? "—").bold()
            }
        }
        .font(.subheadline)
    }
}

private struct SymptomChart: View {
    let summaries: [DaySummary]

    var body: some View {
        if summaries.isEmpty {
            EmptyChartText()
        } else {
            Chart {
                ForEach(summaries) { day in
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("Severity", day.urinaryMax))
                        .foregroundStyle(by: .value("Type", "Urinary"))
                    PointMark(x: .value("Day", day.day, unit: .day), y: .value("Severity", day.urinaryMax))
                        .foregroundStyle(by: .value("Type", "Urinary"))
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("Severity", day.gutMax))
                        .foregroundStyle(by: .value("Type", "Gut"))
                    PointMark(x: .value("Day", day.day, unit: .day), y: .value("Severity", day.gutMax))
                        .foregroundStyle(by: .value("Type", "Gut"))
                }
            }
            .chartYScale(domain: 0...5)
            .chartForegroundStyleScale(["Urinary": Color.orange, "Gut": Color.purple])
        }
    }
}

private struct BristolChart: View {
    let summaries: [DaySummary]

    private struct Point: Identifiable {
        let id = UUID()
        let day: Date
        let type: Int
    }

    var body: some View {
        let points = summaries.flatMap { day in day.bristolTypes.map { Point(day: day.day, type: $0) } }
        if points.isEmpty {
            EmptyChartText()
        } else {
            Chart {
                // The "normal" band.
                RectangleMark(yStart: .value("Low", 2.5), yEnd: .value("High", 4.5))
                    .foregroundStyle(Color.green.opacity(0.12))
                ForEach(points) { point in
                    PointMark(x: .value("Day", point.day, unit: .day), y: .value("Type", Double(point.type)))
                        .foregroundStyle(point.type <= 2 ? Color.brown : (point.type >= 5 ? Color.orange : Color.green))
                }
            }
            .chartYScale(domain: 0.5...7.5)
            .chartYAxis {
                AxisMarks(values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
            }
        }
    }
}

private struct WaterChart: View {
    let summaries: [DaySummary]
    let goal: Int

    var body: some View {
        let days = summaries.filter { $0.water > 0 }
        if days.isEmpty {
            EmptyChartText()
        } else {
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Glasses", day.water))
                        .foregroundStyle(day.water >= goal ? Color.blue : Color.blue.opacity(0.45))
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
    }
}

private struct EmptyChartText: View {
    var body: some View {
        Text("Not enough logged in this range yet.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PatternsSection: View {
    let patterns: [Pattern]

    var body: some View {
        Section {
            if patterns.isEmpty {
                Text("Nothing stands out yet. Patterns need at least \(Patterns.minimumDays) days with and without something (e.g. dairy) to compare — keep tagging your food.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(patterns) { pattern in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(pattern.symptomArea) symptoms worse with: \(pattern.title)")
                            .font(.headline)
                        Text("Average worst severity \(format(pattern.withAverage)) on those days (or the day after) vs \(format(pattern.withoutAverage)) without — \(pattern.withDays) vs \(pattern.withoutDays) days.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Possible patterns (all time)")
        } footer: {
            Text("These are hints, not proof — two things happening on the same days can be coincidence. The usual way to test one is cutting it out for 2–3 weeks and seeing if symptoms change, ideally with a doctor or dietitian.")
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
