import SwiftUI
import SwiftData

struct ContentView: View {
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
                        description: Text("Tap + to jot one down.")
                    )
                } else {
                    List {
                        ForEach(ideas) { idea in
                            NavigationLink(value: idea) {
                                IdeaRow(idea: idea)
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
            modelContext.delete(ideas[index])
        }
    }
}

private struct IdeaRow: View {
    let idea: Idea

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(idea.rawText)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                if idea.status == .processed {
                    Label("\(idea.todoItems.count) steps", systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Not broken down yet", systemImage: "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(idea.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Idea.self, TodoItem.self], inMemory: true)
}
