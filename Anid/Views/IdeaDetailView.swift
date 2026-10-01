import SwiftUI
import SwiftData

struct IdeaDetailView: View {
    @Bindable var idea: Idea
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]

    @AppStorage(SettingsKeys.model) private var modelRaw = GeminiModel.flashLite.rawValue
    @AppStorage(SettingsKeys.knownPlaces) private var knownPlacesRaw = ""
    @State private var isProcessing = false
    @State private var isUploadingVideo = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var isPresentingSettings = false
    @State private var isConfirmingRegenerate = false

    private var selectedModel: GeminiModel {
        GeminiModel(rawValue: modelRaw) ?? .flashLite
    }

    private var hasAPIKey: Bool {
        (KeychainService.loadAPIKey()?.isEmpty == false)
    }

    private var isBusy: Bool {
        isProcessing || isUploadingVideo
    }

    private var sortedTodoItems: [TodoItem] {
        idea.todoItems.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Form {
            Section("Idea") {
                if !idea.rawText.isEmpty {
                    Text(idea.rawText)
                }
                if idea.localVideoFilename != nil {
                    Label("Video attached", systemImage: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let link = idea.sourceURLString, let url = URL(string: link) {
                    Link(link, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            Section {
                GoalPicker(goals: goals, selection: $idea.goal)
            } footer: {
                if idea.status == .processed {
                    Text("Changed the goal? Regenerate the plan so it's built around the new one.")
                } else if goals.isEmpty {
                    Text("Add a goal in the Goals tab to get a plan built around what you're working toward.")
                }
            }

            if let summary = idea.summary {
                Section("What this reel teaches") {
                    Text(summary)
                }
            }

            if let connection = idea.goalConnection {
                Section {
                    Text(connection)
                } header: {
                    Label(idea.goal.map { "Why it helps: \($0.title)" } ?? "Why it helps", systemImage: "target")
                }
            }

            if !idea.prerequisites.isEmpty {
                Section {
                    ForEach(Array(idea.prerequisites.enumerated()), id: \.offset) { _, prerequisite in
                        Label(prerequisite, systemImage: "checkmark.shield")
                    }
                } header: {
                    Text("Before you start")
                } footer: {
                    Text("Missing one of these? Ask about it in the chat below — it can teach you the basics first.")
                }
            }

            if idea.todoItems.isEmpty {
                Section {
                    breakDownButton(title: "Break This Down", systemImage: "sparkles")
                    if !hasAPIKey {
                        Button("Add a Gemini API key in Settings") {
                            isPresentingSettings = true
                        }
                        .font(.caption)
                    }
                } footer: {
                    if idea.goal == nil {
                        Text("Tip: pick a goal above first — the plan will be built around it.")
                    }
                }
            } else {
                Section("Your plan") {
                    ForEach(Array(sortedTodoItems.enumerated()), id: \.element.id) { index, item in
                        TodoRowView(
                            item: item,
                            number: index + 1,
                            isSelected: selectedItemIDs.contains(item.id),
                            onToggleSelect: { toggleSelection(item) }
                        )
                    }
                }

                Section {
                    NavigationLink {
                        IdeaChatView(idea: idea)
                    } label: {
                        Label("Get Help With These Steps", systemImage: "bubble.left.and.bubble.right")
                    }
                    .disabled(!hasAPIKey)
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

                Section {
                    if isBusy {
                        breakDownButton(title: "Regenerate Plan", systemImage: "arrow.clockwise")
                    } else {
                        Button {
                            isConfirmingRegenerate = true
                        } label: {
                            Label("Regenerate Plan", systemImage: "arrow.clockwise")
                        }
                        .disabled(!hasAPIKey)
                    }
                }
            }
        }
        .navigationTitle("Idea")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
        .confirmationDialog(
            "Replace the current plan?",
            isPresented: $isConfirmingRegenerate,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) {
                Task { await regenerate() }
            }
        } message: {
            Text("This replaces the summary, prerequisites, and steps with a fresh plan. Steps already sent to Remind Me stay there.")
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

    private func breakDownButton(title: String, systemImage: String) -> some View {
        Button {
            Task { await breakDown() }
        } label: {
            if isUploadingVideo {
                HStack {
                    ProgressView()
                    Text("Uploading video...")
                }
            } else if isProcessing {
                HStack {
                    ProgressView()
                    Text("Building your plan...")
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .disabled(isBusy || !hasAPIKey)
    }

    private func toggleSelection(_ item: TodoItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    private func regenerate() async {
        // Only clear the old plan once the new one has actually arrived, so
        // a failed request (offline, quota hit) doesn't leave the idea empty.
        let oldItems = idea.todoItems
        await breakDown(replacing: oldItems)
    }

    private func breakDown(replacing oldItems: [TodoItem] = []) async {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            errorMessage = GeminiServiceError.missingAPIKey.localizedDescription
            return
        }
        do {
            defer {
                isUploadingVideo = false
                isProcessing = false
            }

            var videoFile: GeminiUploadedFile?
            if idea.localVideoFilename != nil {
                isUploadingVideo = true
                videoFile = try await GeminiService.ensureUploadedVideo(for: idea, apiKey: apiKey)
                isUploadingVideo = false
            }
            isProcessing = true

            let knownPlaces = SettingsKeys.parsePlaces(knownPlacesRaw)
            let result = try await GeminiService.breakDown(
                idea: idea,
                apiKey: apiKey,
                model: selectedModel,
                knownPlaces: knownPlaces,
                videoFile: videoFile
            )

            // Detach before deleting: a relationship array can keep showing
            // deleted objects until the context next saves.
            let oldIDs = Set(oldItems.map(\.id))
            idea.todoItems.removeAll { oldIDs.contains($0.id) }
            for item in oldItems {
                modelContext.delete(item)
            }

            idea.summary = result.summary
            idea.goalConnection = idea.goal == nil ? nil : result.goalConnection
            idea.prerequisites = result.prerequisites

            // createdAt orders the steps on screen, and inserting in a tight
            // loop can give several items the same timestamp — offset each
            // one so the plan always reads in the order Gemini wrote it.
            let base = Date()
            var newItemIDs: Set<UUID> = []
            for (index, draft) in result.todoItems.enumerated() {
                // Only trust a placeName Gemini returned if it's still one of
                // the user's declared places, in case they edited the list
                // between requests or the model didn't follow instructions.
                let placeName = draft.placeName.flatMap { knownPlaces.contains($0) ? $0 : nil }
                let item = TodoItem(
                    text: draft.text,
                    notes: draft.notes,
                    dueDate: placeName == nil ? draft.dueDate : nil,
                    placeName: placeName,
                    idea: idea
                )
                item.createdAt = base.addingTimeInterval(Double(index) * 0.001)
                modelContext.insert(item)
                newItemIDs.insert(item.id)
            }
            idea.status = .processed
            selectedItemIDs = newItemIDs
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
