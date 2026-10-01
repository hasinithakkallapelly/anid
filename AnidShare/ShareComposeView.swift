import SwiftUI

struct ShareComposeView: View {
    let goals: [Goal]
    let onSave: (String, Goal?) -> Void
    let onCancel: () -> Void

    @State private var note = ""
    @State private var selectedGoal: Goal?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Video attached", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Section("Add a note (optional)") {
                    TextField("What's this about?", text: $note, axis: .vertical)
                        .lineLimit(1...6)
                }
                if !goals.isEmpty {
                    Section {
                        GoalPicker(goals: goals, selection: $selectedGoal)
                    }
                }
            }
            .navigationTitle("Save to Anid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note.trimmingCharacters(in: .whitespacesAndNewlines), selectedGoal)
                    }
                }
            }
        }
    }
}
