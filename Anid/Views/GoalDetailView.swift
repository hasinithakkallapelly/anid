import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Bindable var goal: Goal

    @State private var isEditing = false
    @State private var isAddingIdea = false

    private var sortedIdeas: [Idea] {
        goal.ideas.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            Section {
                Text(goal.title)
                    .font(.title3.bold())
                if let details = goal.details, !details.isEmpty {
                    Text(details)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if sortedIdeas.isEmpty {
                    Text("No reels linked yet. Add one here, or pick this goal when saving a reel.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedIdeas) { idea in
                        NavigationLink(value: idea) {
                            IdeaRow(idea: idea)
                        }
                    }
                }
                Button {
                    isAddingIdea = true
                } label: {
                    Label("Save a Reel for This Goal", systemImage: "plus.circle")
                }
            } header: {
                Text("Reels")
            }
        }
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            GoalEditView(goal: goal)
        }
        .sheet(isPresented: $isAddingIdea) {
            IdeaCaptureView(initialGoal: goal)
        }
    }
}
