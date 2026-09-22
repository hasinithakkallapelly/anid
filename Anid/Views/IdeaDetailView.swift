import SwiftUI
import SwiftData

struct IdeaDetailView: View {
    @Bindable var idea: Idea
    @Environment(\.modelContext) private var modelContext

    @AppStorage(SettingsKeys.model) private var modelRaw = ClaudeModel.opus5.rawValue
    @AppStorage(SettingsKeys.knownPlaces) private var knownPlacesRaw = ""
    @State private var isProcessing = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var isPresentingSettings = false

    private var selectedModel: ClaudeModel {
        ClaudeModel(rawValue: modelRaw) ?? .opus5
    }

    private var hasAPIKey: Bool {
        (KeychainService.loadAPIKey()?.isEmpty == false)
    }

    private var sortedTodoItems: [TodoItem] {
        idea.todoItems.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Form {
            Section("Idea") {
                Text(idea.rawText)
                if let link = idea.sourceURLString, let url = URL(string: link) {
                    Link(link, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            if let summary = idea.summary {
                Section("Summary") {
                    Text(summary)
                }
            }

            if idea.todoItems.isEmpty {
                Section {
                    Button {
                        Task { await breakDown() }
                    } label: {
                        if isProcessing {
                            HStack {
                                ProgressView()
                                Text("Thinking...")
                            }
                        } else {
                            Label("Break This Down", systemImage: "sparkles")
                        }
                    }
                    .disabled(isProcessing || !hasAPIKey)

                    if !hasAPIKey {
                        Button("Add a Claude API key in Settings") {
                            isPresentingSettings = true
                        }
                        .font(.caption)
                    }
                }
            } else {
                Section("Steps") {
                    ForEach(sortedTodoItems) { item in
                        TodoRowView(
                            item: item,
                            isSelected: selectedItemIDs.contains(item.id),
                            onToggleSelect: { toggleSelection(item) }
                        )
                    }
                }

                Section {
                    Button {
                        Task { await sendSelected() }
                    } label: {
                        if isSending {
                            HStack {
                                ProgressView()
                                Text("Sending...")
                            }
                        } else {
                            Label("Send Selected to Remind Me (\(selectedItemIDs.count))", systemImage: "arrow.up.forward.app")
                        }
                    }
                    .disabled(selectedItemIDs.isEmpty || isSending)
                }
            }
        }
        .navigationTitle("Idea")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in if !isPresented { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            selectedItemIDs = Set(idea.todoItems.filter { !$0.isSentToRemindMe }.map(\.id))
        }
    }

    private func toggleSelection(_ item: TodoItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    private func breakDown() async {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            errorMessage = ClaudeServiceError.missingAPIKey.localizedDescription
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let knownPlaces = SettingsKeys.parsePlaces(knownPlacesRaw)
            let result = try await ClaudeService.breakDown(
                idea: idea,
                apiKey: apiKey,
                model: selectedModel,
                knownPlaces: knownPlaces
            )
            idea.summary = result.summary
            for draft in result.todoItems {
                // Defensive re-check: only trust a placeName Claude returned if it's
                // still one of the user's declared places, in case they edited the
                // list between requests or the model didn't follow instructions.
                let placeName = draft.placeName.flatMap { knownPlaces.contains($0) ? $0 : nil }
                let item = TodoItem(
                    text: draft.text,
                    notes: draft.notes,
                    dueDate: placeName == nil ? draft.dueDate : nil,
                    placeName: placeName,
                    idea: idea
                )
                modelContext.insert(item)
            }
            idea.status = .processed
            selectedItemIDs = Set(idea.todoItems.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendSelected() async {
        let items = idea.todoItems.filter { selectedItemIDs.contains($0.id) }
        guard !items.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await RemindMeBridge.send(items)
            for item in items {
                item.isSentToRemindMe = true
            }
            selectedItemIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
