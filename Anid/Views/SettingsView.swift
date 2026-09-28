import SwiftUI

enum SettingsKeys {
    static let model = "geminiModel"
    static let knownPlaces = "knownRemindMePlaces"

    static func parsePlaces(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.model) private var modelRaw = GeminiModel.flashLite.rawValue
    @AppStorage(SettingsKeys.knownPlaces) private var knownPlacesRaw = ""

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var remindMeInstalled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(hasStoredKey ? "•••••••••••• (saved)" : "AIza...", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Key") { saveKey() }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasStoredKey {
                        Button("Remove Key", role: .destructive) { removeKey() }
                    }
                } header: {
                    Text("Gemini API Key")
                } footer: {
                    Text("Get a free key at aistudio.google.com → Get API key. No credit card required. Free daily request caps vary by model (see below) and Google changes them without much notice, but personal use is unlikely to hit them. The key is stored in the Keychain and only ever sent to generativelanguage.googleapis.com.")
                }

                Section {
                    Picker("Model", selection: $modelRaw) {
                        ForEach(GeminiModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Both are free. Flash-Lite has a much higher free daily request cap, so it's the safer default for everyday use; Flash gives more thorough breakdowns but its free tier runs out much faster. Google has changed these limits and model names before without much warning — if you ever see a \"model no longer available\" error, that error message names the replacement.")
                }

                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(remindMeInstalled ? "Found" : "Not found")
                            .foregroundStyle(remindMeInstalled ? .green : .secondary)
                    }
                } header: {
                    Text("Remind Me")
                } footer: {
                    Text("Requires the Remind Me app on this device, with its reminder-import link support added — see Docs/RemindMeIntegration.md in this project.")
                }

                Section {
                    TextField("Room, Gym, Kitchen, Office", text: $knownPlacesRaw)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Your Remind Me Places")
                } footer: {
                    Text("Comma-separated names of the places you've already saved in Remind Me — spelled exactly as they are there. Anid can't read Remind Me's place list directly, so when Gemini thinks a step belongs at a place (like a laptop task → \"Room\") it can only pick from names you list here, and Remind Me matches reminders to real places by exact name.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                hasStoredKey = (KeychainService.loadAPIKey()?.isEmpty == false)
                remindMeInstalled = RemindMeBridge.isRemindMeInstalled
            }
        }
    }

    private func saveKey() {
        KeychainService.save(apiKey: apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
        apiKeyInput = ""
        hasStoredKey = true
    }

    private func removeKey() {
        KeychainService.deleteAPIKey()
        hasStoredKey = false
    }
}

#Preview {
    SettingsView()
}
