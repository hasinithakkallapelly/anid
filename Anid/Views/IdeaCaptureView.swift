import SwiftUI
import SwiftData

struct IdeaCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var link = ""
    @FocusState private var isTextFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("What's the idea?") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .focused($isTextFocused)
                }
                Section("Reel or article link (optional)") {
                    TextField("https://instagram.com/reel/...", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Paste the link and add a line about what it's about. Claude can't read a reel from the link alone — there's no way to fetch someone else's reel content automatically — so what you type above is what actually gets processed.")
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
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isTextFocused = true }
        }
    }

    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let idea = Idea(rawText: trimmedText, sourceURLString: trimmedLink.isEmpty ? nil : trimmedLink)
        modelContext.insert(idea)
        dismiss()
    }
}

#Preview {
    IdeaCaptureView()
        .modelContainer(for: [Idea.self, TodoItem.self], inMemory: true)
}
