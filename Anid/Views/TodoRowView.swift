import SwiftUI

struct TodoRowView: View {
    @Bindable var item: TodoItem
    let isSelected: Bool
    let onToggleSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(item.isSentToRemindMe)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.isSentToRemindMe {
                    Label("Sent to Remind Me", systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    TriggerControl(item: item)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Lets the user confirm or override how Claude classified a step: fire at
/// a place (geofence, in Remind Me), fire at a time, or no reminder trigger
/// at all — just a plain step. Claude's guess pre-fills this but the user
/// has the final say, since Anid can't verify a suggested place actually
/// exists in Remind Me.
private struct TriggerControl: View {
    @Bindable var item: TodoItem
    @AppStorage(SettingsKeys.knownPlaces) private var knownPlacesRaw = ""
    @State private var mode: TriggerMode

    private enum TriggerMode: String, CaseIterable {
        case none = "None"
        case time = "Time"
        case place = "Place"
    }

    init(item: TodoItem) {
        self.item = item
        if item.placeName != nil {
            _mode = State(initialValue: .place)
        } else if item.dueDate != nil {
            _mode = State(initialValue: .time)
        } else {
            _mode = State(initialValue: .none)
        }
    }

    private var knownPlaces: [String] {
        SettingsKeys.parsePlaces(knownPlacesRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Trigger", selection: $mode) {
                ForEach(TriggerMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .font(.caption)
            .onChange(of: mode) { _, newMode in
                switch newMode {
                case .none:
                    item.dueDate = nil
                    item.placeName = nil
                case .time:
                    item.placeName = nil
                    if item.dueDate == nil { item.dueDate = Date() }
                case .place:
                    item.dueDate = nil
                    if item.placeName == nil || !knownPlaces.contains(item.placeName!) {
                        item.placeName = knownPlaces.first
                    }
                }
            }

            switch mode {
            case .none:
                EmptyView()
            case .time:
                DatePicker(
                    "",
                    selection: Binding(
                        get: { item.dueDate ?? Date() },
                        set: { item.dueDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            case .place:
                if knownPlaces.isEmpty {
                    Text("Add your Remind Me place names in Settings to use this.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Place", selection: Binding(
                        get: { item.placeName ?? knownPlaces.first ?? "" },
                        set: { item.placeName = $0 }
                    )) {
                        ForEach(knownPlaces, id: \.self) { place in
                            Text(place).tag(place)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}
