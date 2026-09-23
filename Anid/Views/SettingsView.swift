import SwiftUI

enum SettingsKeys {
    static let model = "claudeModel"
    static let knownPlaces = "knownRemindMePlaces"

    static func parsePlaces(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.model) private var modelRaw = ClaudeModel.opus5.rawValue
    @AppStorage(SettingsKeys.knownPlaces) private var knownPlacesRaw = ""

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var remindMeInstalled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(hasStoredKey ? "•••••••••••• (saved)" : "sk-ant-...", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Key") { saveKey() }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasStoredKey {
                        Button("Remove Key", role: .destructive) { removeKey() }
                    }
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Get a key at console.anthropic.com → API Keys. Usage is billed per token by Anthropic — typically a few cents per idea processed. The key is stored in the Keychain and only ever sent to api.anthropic.com.")
                }

                Section {
                    Picker("Model", selection: $modelRaw) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Opus 5 gives the most thorough breakdowns. Sonnet 5 or Haiku 4.5 cost less if you're processing a lot of ideas.")
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
                    Text("Comma-separated names of the places you've already saved in Remind Me — spelled exactly as they are there. Anid can't read Remind Me's place list directly, so when Claude thinks a step belongs at a place (like a laptop task → \"Room\") it can only pick from names you list here, and Remind Me matches reminders to real places by exact name.")
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
        KeychainService.save(apiKey: apiKeyInput.trimmingCharacters(in: .whitespaces))
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
