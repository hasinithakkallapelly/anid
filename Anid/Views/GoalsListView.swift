import SwiftUI
import SwiftData

struct GoalsListView: View {
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Environment(\.modelContext) private var modelContext

    @State private var isPresentingNewGoal = false

    var body: some View {
        NavigationStack {
            Group {
                if goals.isEmpty {
                    ContentUnavailableView {
                        Label("No goals yet", systemImage: "target")
                    } description: {
                        Text("Add what you're working toward — like \"Learn guitar\" or \"Get better at iOS dev\" — and link saved reels to it. Breakdowns then plan around the goal, not just the reel.")
                    } actions: {
                        Button("Add a Goal") { isPresentingNewGoal = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(goals) { goal in
                            NavigationLink(value: goal) {
                                GoalRow(goal: goal)
                            }
                        }
                        .onDelete(perform: deleteGoals)
                    }
                }
            }
            .navigationTitle("Goals")
            .navigationDestination(for: Goal.self) { goal in
                GoalDetailView(goal: goal)
            }
            .navigationDestination(for: Idea.self) { idea in
                IdeaDetailView(idea: idea)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingNewGoal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingNewGoal) {
            GoalEditView(goal: nil)
        }
    }

    private func deleteGoals(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(goals[index])
        }
    }
}

private struct GoalRow: View {
    let goal: Goal

    var body: some View {
        let total = goal.ideas.count
        let brokenDown = goal.ideas.filter { $0.status == .processed }.count
        VStack(alignment: .leading, spacing: 4) {
            Text(goal.title)
                .font(.headline)
            if let details = goal.details, !details.isEmpty {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(total == 0 ? "No reels linked yet" : "\(total) reel\(total == 1 ? "" : "s") · \(brokenDown) broken down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
