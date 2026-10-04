import SwiftUI
import SwiftData

struct EditorRequest: Identifiable {
    let id = UUID()
    let kind: EventKind
    let event: LogEvent?
}

/// Everything logged for one day. Used by the Today tab and when opening a
/// past day from History.
struct DayView: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKeys.waterGoal) private var waterGoal = SettingsKeys.defaultWaterGoal
    @AppStorage(SettingsKeys.trackPeriod) private var trackPeriod = false

    @Query private var events: [LogEvent]
    @State private var dayLog: DayLog?
    @State private var editor: EditorRequest?

    init(day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        self.day = start
        _events = Query(
            filter: #Predicate<LogEvent> { $0.timestamp >= start && $0.timestamp < end },
            sort: \LogEvent.timestamp,
            order: .reverse
        )
    }

    var body: some View {
        List {
            if events.contains(where: \.isRedFlag) {
                Section {
                    RedFlagBanner(events: events)
                }
            }

            Section("Add") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 8) {
                    ForEach(EventKind.allCases) { kind in
                        Button {
                            editor = EditorRequest(kind: kind, event: nil)
                        } label: {
                            Label(kind.label, systemImage: kind.systemImage)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Daily") {
                CounterRow(
                    title: "Water",
                    systemImage: "drop.fill",
                    value: binding(\.waterGlasses, default: 0),
                    suffix: "/ \(waterGoal) glasses"
                )
                CounterRow(
                    title: "Times peed",
                    systemImage: "toilet",
                    value: binding(\.urinations, default: 0),
                    suffix: nil
                )
                SleepRow(hours: binding(\.sleepHours, default: nil))
                RatingRow(title: "Stress", low: "Calm", high: "Very stressed", value: binding(\.stress, default: nil))
                RatingRow(title: "Overall feeling", low: "Awful", high: "Great", value: binding(\.feeling, default: nil))
                if trackPeriod {
                    Toggle("On period", isOn: binding(\.onPeriod, default: false))
                }
                TextField("Notes about the day", text: binding(\.notes, default: ""), axis: .vertical)
                    .lineLimit(1...5)
            }

            Section("Timeline") {
                if events.isEmpty {
                    Text("Nothing logged yet. Use the buttons above.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        Button {
                            editor = EditorRequest(kind: event.kind, event: event)
                        } label: {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(events[index]) }
                    }
                }
            }
        }
        .task(id: DayKey.string(for: day)) {
            dayLog = DayLog.fetch(for: day, in: modelContext)
        }
        .sheet(item: $editor) { request in
            EventEditorView(kind: request.kind, event: request.event, day: day)
        }
    }

    /// Reads from the day's DayLog, and only creates it on the first edit so
    /// that just looking at a day doesn't add an empty entry to History.
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<DayLog, T>, default fallback: T) -> Binding<T> {
        // Ignore a DayLog still loaded from the previously shown day.
        let current = dayLog?.dayKey == DayKey.string(for: day) ? dayLog : nil
        return Binding(
            get: { current?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                let log = current ?? DayLog.fetchOrCreate(for: day, in: modelContext)
                log[keyPath: keyPath] = newValue
                dayLog = log
            }
        )
    }
}

struct EventRow: View {
    let event: LogEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.systemImage)
                .foregroundStyle(event.isRedFlag ? Color.red : Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(event.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        var parts: [String] = []
        switch event.kind {
        case .symptom:
            if let severity = event.severity { parts.append(Catalog.severityLabel(severity)) }
        case .bowel:
            if let bristol = event.bristol { parts.append(Catalog.bristolMeaning(bristol)) }
            if let severity = event.severity { parts.append("pain \(severity)/5") }
            parts.append(contentsOf: event.tags)
        case .food:
            parts.append(contentsOf: event.tags)
        case .medication, .note:
            break
        }
        if !event.detail.isEmpty { parts.append(event.detail) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct RedFlagBanner: View {
    let events: [LogEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Worth calling a doctor", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            if events.contains(where: { $0.kind == .symptom && $0.isRedFlag }) {
                Text("Fever, back/side pain, or blood in urine alongside UTI symptoms can mean the infection has reached the kidneys. Don't wait it out — get seen today.")
            }
            if events.contains(where: { $0.kind == .bowel && $0.isRedFlag }) {
                Text("Blood in your poop isn't a typical IBS symptom. Mention it to a doctor, especially if it happens more than once.")
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

private struct CounterRow: View {
    let title: String
    let systemImage: String
    @Binding var value: Int
    let suffix: String?

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("\(value)").monospacedDigit().bold()
            if let suffix {
                Text(suffix).foregroundStyle(.secondary).font(.caption)
            }
            Stepper(title, value: $value, in: 0...50)
                .labelsHidden()
        }
    }
}

private struct SleepRow: View {
    @Binding var hours: Double?

    var body: some View {
        HStack {
            Label("Sleep", systemImage: "bed.double.fill")
            Spacer()
            Text(hours.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) h" } ?? "—")
                .monospacedDigit()
                .bold()
            Stepper("Sleep") {
                hours = hours.map { min($0 + 0.5, 16) } ?? 7
            } onDecrement: {
                hours = hours.map { max($0 - 0.5, 0) } ?? 7
            }
            .labelsHidden()
        }
    }
}

/// Five tappable dots. Tapping the selected one again clears it.
struct RatingRow: View {
    let title: String
    let low: String
    let high: String
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            HStack {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        value = (value == level) ? nil : level
                    } label: {
                        Text("\(level)")
                            .font(.callout.bold())
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(level == value ? Color.accentColor : Color.secondary.opacity(0.15)))
                            .foregroundStyle(level == value ? Color.white : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    if level < 5 { Spacer() }
                }
            }
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
