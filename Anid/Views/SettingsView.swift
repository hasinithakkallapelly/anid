import SwiftUI

enum SettingsKeys {
    static let model = "claudeModel"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.model) private var modelRaw = ClaudeModel.opus5.rawValue

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var remindMeInstalled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Claude API Key") {
                    SecureField(hasStoredKey ? "•••••••••••• (saved)" : "sk-ant-...", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Key") { saveKey() }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasStoredKey {
                        Button("Remove Key", role: .destructive) { removeKey() }
                    }
                } footer: {
                    Text("Get a key at console.anthropic.com → API Keys. Usage is billed per token by Anthropic — typically a few cents per idea processed. The key is stored in the Keychain and only ever sent to api.anthropic.com.")
                }

                Section("Model") {
                    Picker("Model", selection: $modelRaw) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                } footer: {
                    Text("Opus 5 gives the most thorough breakdowns. Sonnet 5 or Haiku 4.5 cost less if you're processing a lot of ideas.")
                }

                Section("Remind Me") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(remindMeInstalled ? "Found" : "Not found")
                            .foregroundStyle(remindMeInstalled ? .green : .secondary)
                    }
                } footer: {
                    Text("Requires the Remind Me app on this device, with its reminder-import link support added — see Docs/RemindMeIntegration.md in this project.")
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
