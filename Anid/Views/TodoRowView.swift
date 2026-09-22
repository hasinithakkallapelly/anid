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
                    DueDateControl(item: item)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DueDateControl: View {
    @Bindable var item: TodoItem
    @State private var hasDueDate: Bool

    init(item: TodoItem) {
        self.item = item
        _hasDueDate = State(initialValue: item.dueDate != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Due date", isOn: $hasDueDate.animation())
                .font(.caption)
                .onChange(of: hasDueDate) { _, newValue in
                    item.dueDate = newValue ? (item.dueDate ?? Date()) : nil
                }
            if hasDueDate {
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
            }
        }
    }
}
