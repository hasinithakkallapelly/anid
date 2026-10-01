import SwiftUI

struct ShareComposeView: View {
    @State private var note = ""
    let onSave: (String) -> Void
    let onCancel: () -> Void

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
            }
            .navigationTitle("Save to Anid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
    }
}
