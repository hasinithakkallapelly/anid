import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            IdeasListView()
                .tabItem { Label("Ideas", systemImage: "lightbulb") }
            GoalsListView()
                .tabItem { Label("Goals", systemImage: "target") }
        }
    }
}

private struct IdeasListView: View {
    @Query(sort: \Idea.createdAt, order: .reverse) private var ideas: [Idea]
    @Environment(\.modelContext) private var modelContext

    @State private var isPresentingCapture = false
    @State private var isPresentingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if ideas.isEmpty {
                    ContentUnavailableView(
                        "No ideas yet",
                        systemImage: "lightbulb",
                        description: Text("Tap + to save a reel or jot down an idea.")
                    )
                } else {
                    List {
                        ForEach(ideas) { idea in
                            NavigationLink(value: idea) {
                                IdeaRow(idea: idea, showsGoal: true)
                            }
                        }
                        .onDelete(perform: deleteIdeas)
                    }
                }
            }
            .navigationTitle("Anid")
            .navigationDestination(for: Idea.self) { idea in
                IdeaDetailView(idea: idea)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPresentingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingCapture = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingCapture) {
            IdeaCaptureView()
        }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
    }

    private func deleteIdeas(at offsets: IndexSet) {
        for index in offsets {
            let idea = ideas[index]
            if let filename = idea.localVideoFilename {
                VideoStorage.delete(filename: filename)
            }
            modelContext.delete(idea)
        }
    }
}

struct IdeaRow: View {
    let idea: Idea
    var showsGoal = false

    private var title: String {
        if !idea.rawText.isEmpty { return idea.rawText }
        if let summary = idea.summary { return summary }
        return idea.localVideoFilename != nil ? "Saved reel" : "Untitled idea"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 8) {
                if idea.status == .processed {
                    let done = idea.todoItems.filter(\.isSentToRemindMe).count
                    Label("\(idea.todoItems.count) steps", systemImage: "checklist")
                    if done > 0 {
                        Text("\(done) sent")
                    }
                } else {
                    Label("Not broken down yet", systemImage: "circle.dashed")
                }
                if idea.localVideoFilename != nil {
                    Image(systemName: "video.fill")
                }
                Spacer()
                Text(idea.createdAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if showsGoal, let goal = idea.goal {
                Label(goal.title, systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Idea.self, TodoItem.self, ChatMessage.self, Goal.self], inMemory: true)
}
