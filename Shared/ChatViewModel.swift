import Foundation
import SwiftUI

@MainActor
public final class ChatViewModel: ObservableObject {
    public let agent: Agent
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var isStreaming = false
    @Published public private(set) var streamingText = ""
    @Published public var errorMessage: String?

    private var streamTask: Task<Void, Never>?

    public init(agent: Agent) {
        self.agent = agent
    }

    // MARK: - Load history

    public func loadHistory() async {
        guard let client = ConnectionStore.shared.client else { return }
        do {
            messages = try await client.messages(agentId: agent.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Send

    public func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let client = ConnectionStore.shared.client else {
            errorMessage = RelayError.notConfigured.errorDescription
            return
        }

        // Optimistic local message
        let userMsg = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: text,
            createdAt: Date()
        )
        messages.append(userMsg)
        isStreaming = true
        streamingText = ""
        errorMessage = nil

        streamTask = Task {
            var full = ""
            do {
                for try await chunk in client.chat(agentId: agent.id, text: text) {
                    guard !Task.isCancelled else { break }
                    full += chunk
                    streamingText = full
                }
                // Commit streamed reply
                let reply = ChatMessage(
                    id: UUID().uuidString,
                    role: "assistant",
                    content: full,
                    createdAt: Date()
                )
                messages.append(reply)
                Speaker.shared.speak(full)
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isStreaming = false
            streamingText = ""
        }
    }

    // MARK: - Quick replies

    public func quickReply(_ text: String) {
        send(text)
    }

    // MARK: - Stop

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        streamingText = ""
    }
}
