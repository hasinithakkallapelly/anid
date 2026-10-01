import SwiftUI
import SwiftData

/// Creates a new goal when `goal` is nil, otherwise edits the given one.
struct GoalEditView: View {
    let goal: Goal?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("e.g. Learn to build iOS apps", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isTitleFocused)
                }
                Section {
                    TextField("Where you're starting from, what \"done\" looks like, any deadline...", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Details (optional)")
                } footer: {
                    Text("Sent to Gemini with every reel linked to this goal, so it can pitch prerequisites and steps at your actual level. E.g. \"Complete beginner, never coded. Want to ship a simple app to my own phone in 3 months.\"")
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let goal {
                    title = goal.title
                    details = goal.details ?? ""
                } else {
                    isTitleFocused = true
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if let goal {
            goal.title = trimmedTitle
            goal.details = trimmedDetails.isEmpty ? nil : trimmedDetails
        } else {
            modelContext.insert(Goal(title: trimmedTitle, details: trimmedDetails.isEmpty ? nil : trimmedDetails))
        }
        dismiss()
    }
}
