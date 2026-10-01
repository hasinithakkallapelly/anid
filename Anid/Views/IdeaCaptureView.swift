import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct IdeaCaptureView: View {
    var initialGoal: Goal?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]

    @State private var text = ""
    @State private var link = ""
    @State private var selectedGoal: Goal?
    @FocusState private var isTextFocused: Bool

    @State private var pickedVideoItem: PhotosPickerItem?
    @State private var pickedVideoURL: URL?
    @State private var isImportingVideo = false
    @State private var importError: String?

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pickedVideoURL != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $pickedVideoItem, matching: .videos) {
                        if isImportingVideo {
                            HStack {
                                ProgressView()
                                Text("Importing video...")
                            }
                        } else if pickedVideoURL != nil {
                            Label("Video attached", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Attach the reel's video", systemImage: "video.badge.plus")
                        }
                    }
                    if pickedVideoURL != nil {
                        Button("Remove Video", role: .destructive) {
                            pickedVideoURL = nil
                            pickedVideoItem = nil
                        }
                    }
                } header: {
                    Text("Video (optional, but recommended)")
                } footer: {
                    Text("Save the reel to your Photos library first (Instagram's own Save option), then attach it here — Gemini can actually watch and listen to it. Pasting a link alone doesn't give Gemini anything to work with; there's no way to fetch someone else's reel content automatically.")
                }

                Section("What's the idea?") {
                    TextField("A quick note...", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isTextFocused)
                }

                Section {
                    GoalPicker(goals: goals, selection: $selectedGoal)
                } footer: {
                    if goals.isEmpty {
                        Text("Add goals in the Goals tab to plan reels around what you're working toward.")
                    }
                }

                Section {
                    TextField("https://instagram.com/reel/...", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Reel or article link (optional)")
                } footer: {
                    Text("Just for your own reference — not something Gemini can fetch content from.")
                }
            }
            .navigationTitle("New Idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                selectedGoal = initialGoal
                isTextFocused = true
            }
            .onChange(of: pickedVideoItem) { _, newItem in
                guard let newItem else { return }
                Task { await importVideo(from: newItem) }
            }
            .alert(
                "Couldn't attach video",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { isPresented in if !isPresented { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func importVideo(from item: PhotosPickerItem) async {
        isImportingVideo = true
        defer { isImportingVideo = false }
        do {
            guard let transferred = try await item.loadTransferable(type: TransferableVideo.self) else {
                importError = "Couldn't read that video."
                return
            }
            pickedVideoURL = transferred.url
        } catch {
            importError = error.localizedDescription
        }
    }

    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)

        var storedFilename: String?
        if let pickedVideoURL {
            storedFilename = try? VideoStorage.store(from: pickedVideoURL)
        }

        let idea = Idea(
            rawText: trimmedText,
            sourceURLString: trimmedLink.isEmpty ? nil : trimmedLink,
            localVideoFilename: storedFilename,
            goal: selectedGoal
        )
        modelContext.insert(idea)
        dismiss()
    }
}

/// Lets a video picked in PhotosPicker be read as a local file URL. The
/// system hands back a temporary file that's gone once the picker closes,
/// so this is only used to get it somewhere IdeaCaptureView can copy it
/// from via VideoStorage before that happens.
private struct TransferableVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

#Preview {
    IdeaCaptureView()
        .modelContainer(for: [Idea.self, TodoItem.self, ChatMessage.self, Goal.self], inMemory: true)
}
