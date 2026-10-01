import SwiftUI

struct TodoRowView: View {
    @Bindable var item: TodoItem
    let number: Int
    let isSelected: Bool
    let onToggleSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            // .borderless so taps on the row's other controls (the reminder
            // menu) don't also toggle selection — List rows otherwise treat
            // the whole row as one big button.
            .buttonStyle(.borderless)
            .disabled(item.isSentToRemindMe)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(number). \(item.text)")
                    .font(.headline)

                if let details = item.notes, !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if item.isSentToRemindMe {
                    Label("Sent to Remind Me", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    ReminderControl(item: item)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// A compact reminder setting per step: none, a time, or one of the user's
/// Remind Me places. Gemini's guess pre-fills it, but the user has the
/// final say, since Anid can't verify a suggested place exists in Remind Me.
private struct ReminderControl: View {
    @Bindable var item: TodoItem
    @AppStorage(SettingsKeys.knownPlaces) private var knownPlacesRaw = ""

    private var knownPlaces: [String] {
        SettingsKeys.parsePlaces(knownPlacesRaw)
    }

    private var label: String {
        if let place = item.placeName { return "At \(place)" }
        if let due = item.dueDate { return due.formatted(date: .abbreviated, time: .shortened) }
        return "No reminder"
    }

    private var icon: String {
        if item.placeName != nil { return "mappin.circle" }
        if item.dueDate != nil { return "clock" }
        return "bell.slash"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Button {
                    item.dueDate = nil
                    item.placeName = nil
                } label: {
                    Label("No reminder", systemImage: "bell.slash")
                }
                Button {
                    item.placeName = nil
                    item.dueDate = item.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())
                } label: {
                    Label("At a time", systemImage: "clock")
                }
                if knownPlaces.isEmpty {
                    Text("Add Remind Me places in Settings for place reminders")
                } else {
                    Section("At a place") {
                        ForEach(knownPlaces, id: \.self) { place in
                            Button {
                                item.dueDate = nil
                                item.placeName = place
                            } label: {
                                Label(place, systemImage: "mappin.circle")
                            }
                        }
                    }
                }
            } label: {
                Label(label, systemImage: icon)
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            if item.dueDate != nil {
                DatePicker(
                    "Remind me at",
                    selection: Binding(
                        get: { item.dueDate ?? Date() },
                        set: { item.dueDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
    }
}
