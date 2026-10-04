import SwiftUI
import SwiftData

/// Every day that has anything logged, newest first.
struct HistoryView: View {
    @Query(sort: \LogEvent.timestamp, order: .reverse) private var events: [LogEvent]
    @Query(sort: \DayLog.day, order: .reverse) private var dayLogs: [DayLog]

    private var days: [DaySummary] {
        DaySummary.build(events: events, dayLogs: dayLogs)
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged yet",
                        systemImage: "calendar",
                        description: Text("Days you log on the Today tab show up here.")
                    )
                } else {
                    List(days) { summary in
                        NavigationLink(value: summary.day) {
                            DaySummaryRow(summary: summary)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Date.self) { day in
                DayView(day: day)
                    .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct DaySummaryRow: View {
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.day.formatted(.dateTime.weekday(.abbreviated).day().month()))
                    .font(.headline)
                if summary.hasRedFlag {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                Spacer()
                if let feeling = summary.feeling {
                    Text("Feeling \(feeling)/5").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                if summary.urinaryMax > 0 {
                    Label("UTI \(summary.urinaryMax)", systemImage: "drop.triangle")
                }
                if summary.gutMax > 0 {
                    Label("Gut \(summary.gutMax)", systemImage: "bolt.heart")
                }
                if !summary.bristolTypes.isEmpty {
                    Label(summary.bristolTypes.map(String.init).joined(separator: ","), systemImage: "toilet")
                }
                if summary.water > 0 {
                    Label("\(summary.water)", systemImage: "drop.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !summary.topSymptoms.isEmpty {
                Text(summary.topSymptoms.joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
