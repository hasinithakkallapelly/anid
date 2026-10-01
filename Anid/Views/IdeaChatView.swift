import SwiftUI
import SwiftData
import UIKit

struct IdeaChatView: View {
    @Bindable var idea: Idea
    @Environment(\.modelContext) private var modelContext

    @AppStorage(SettingsKeys.model) private var modelRaw = GeminiModel.flashLite.rawValue
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var selectedModel: GeminiModel {
        GeminiModel(rawValue: modelRaw) ?? .flashLite
    }

    private var sortedMessages: [ChatMessage] {
        idea.chatMessages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            if sortedMessages.isEmpty {
                ContentUnavailableView(
                    "Ask about this idea",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Go deeper on a step, troubleshoot, or ask for more detail.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedMessages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            if isSending {
                                HStack {
                                    ProgressView()
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: sortedMessages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onAppear {
                        scrollToBottom(proxy)
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask something...", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = sortedMessages.last?.id else { return }
        withAnimation {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            errorMessage = GeminiServiceError.missingAPIKey.localizedDescription
            return
        }

        let historyBeforeThisTurn = sortedMessages
        let userMessage = ChatMessage(role: .user, text: trimmed, idea: idea)
        modelContext.insert(userMessage)
        draft = ""

        isSending = true
        defer { isSending = false }
        do {
            let videoFile = try await GeminiService.ensureUploadedVideo(for: idea, apiKey: apiKey)
            let reply = try await GeminiService.sendChatMessage(
                idea: idea,
                apiKey: apiKey,
                model: selectedModel,
                videoFile: videoFile,
                history: historyBeforeThisTurn,
                newMessage: trimmed
            )
            let replyMessage = ChatMessage(role: .model, text: reply, idea: idea)
            modelContext.insert(replyMessage)
        } catch {
            modelContext.delete(userMessage)
            draft = trimmed
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.role == .user ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == .model { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }
}
