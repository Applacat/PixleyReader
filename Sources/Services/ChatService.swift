import Foundation
import FoundationModels

// MARK: - Context Mode

enum ContextMode: Sendable {
    case fullDocument    // First question, full doc fits
    case truncated       // First question, doc was truncated
    case conversation    // Follow-up, using chat history
}

// MARK: - Context Estimate

struct ContextEstimate: Sendable {
    let usedChars: Int
    let maxChars: Int
    let mode: ContextMode

    var percentage: Double {
        min(1.0, Double(usedChars) / Double(maxChars))
    }

    var usedTokensApprox: Int {
        usedChars / 4
    }

    var maxTokensApprox: Int {
        maxChars / 4
    }

    var modeLabel: String {
        switch mode {
        case .fullDocument: return "Full doc"
        case .truncated: return "Truncated"
        case .conversation: return "Chat"
        }
    }

    var modeIcon: String {
        switch mode {
        case .fullDocument: return "doc.text"
        case .truncated: return "doc.badge.ellipsis"
        case .conversation: return "bubble.left.and.bubble.right"
        }
    }

    var isHighUsage: Bool {
        percentage > 0.9
    }

    var isMediumUsage: Bool {
        percentage > 0.7 && percentage <= 0.9
    }
}

// MARK: - Chat Service

/// Service for AI chat functionality - extracts business logic from ChatView for testability.
@MainActor
final class ChatService {

    // MARK: - Context Estimation

    /// Calculate context estimate for the memory meter
    func estimateContext(
        documentLength: Int,
        messages: [ChatMessage]
    ) -> ContextEstimate {
        let hasHistory = !messages.isEmpty

        if hasHistory {
            // Conversation mode: brief doc + chat history
            let historyChars = messages.suffix(ChatConfiguration.recentMessageCount).reduce(0) { $0 + $1.content.count }
            let docChars = min(ChatConfiguration.conversationDocExcerpt, documentLength)
            let totalChars = docChars + historyChars + ChatConfiguration.promptOverhead
            return ContextEstimate(
                usedChars: totalChars,
                maxChars: ChatConfiguration.maxContextChars,
                mode: .conversation
            )
        } else {
            // Full document mode
            let docChars = min(ChatConfiguration.maxContextLength, documentLength)
            let totalChars = docChars + ChatConfiguration.promptOverhead
            return ContextEstimate(
                usedChars: totalChars,
                maxChars: ChatConfiguration.maxContextChars,
                mode: documentLength > ChatConfiguration.maxContextLength ? .truncated : .fullDocument
            )
        }
    }

    // MARK: - Document Truncation

    /// Truncate document if it exceeds max context length
    func truncateDocument(_ content: String) -> (text: String, wasTruncated: Bool) {
        let wasTruncated = content.count > ChatConfiguration.maxContextLength

        if wasTruncated {
            let truncated = String(content.prefix(ChatConfiguration.maxContextLength))
            return (truncated + "\n\n[... document truncated for length ...]", true)
        } else {
            return (content, false)
        }
    }

    // MARK: - Prompt Building

    /// Build the prompt for the AI request
    func buildPrompt(
        question: String,
        documentContent: String,
        priorMessages: [ChatMessage]
    ) -> String {
        let hasConversationHistory = !priorMessages.isEmpty
        let (context, _) = truncateDocument(documentContent)

        if hasConversationHistory {
            // Include recent chat history for follow-up questions
            let recentHistory = priorMessages.suffix(ChatConfiguration.recentMessageCount)
            let historyText = recentHistory.map { msg in
                let role = msg.role == .user ? "User" : "Assistant"
                return "\(role): \(msg.content)"
            }.joined(separator: "\n\n")

            return """
            Document context (for reference):
            ---
            \(context.prefix(ChatConfiguration.conversationDocExcerpt))...
            ---

            Previous conversation:
            \(historyText)

            User's new question: \(question)
            """
        } else {
            // First question - include full document context
            return """
            Document content:
            ---
            \(context)
            ---

            Question: \(question)
            """
        }
    }

    // MARK: - System Prompt

    var systemPrompt: String {
        """
        You are a helpful assistant analyzing a markdown document.
        Answer questions about the document concisely and accurately.
        If the answer is not in the document, say so.
        When the user asks follow-up questions about your previous responses,
        refer to the conversation history rather than re-analyzing the document.
        """
    }

    // MARK: - AI Request

    /// Send a question to the AI and get a response
    func askAI(
        question: String,
        documentContent: String,
        priorMessages: [ChatMessage]
    ) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        let prompt = buildPrompt(
            question: question,
            documentContent: documentContent,
            priorMessages: priorMessages
        )

        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Availability Check

    /// Check if Apple Intelligence is available
    func checkAvailability() -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    // MARK: - Document Loading Coordination

    /// Result of waiting for document content
    enum DocumentWaitResult {
        case loaded
        case timeout
        case alreadyLoaded
    }

    /// Wait for document content with timeout using structured concurrency.
    /// Returns the result indicating if document loaded, timed out, or was already available.
    func waitForDocument(
        isCurrentlyEmpty: Bool,
        setLoadCallback: (@escaping @MainActor () -> Void) -> Void,
        clearLoadCallback: () -> Void,
        timeout: Duration = .seconds(3)
    ) async -> DocumentWaitResult {
        // Document already has content
        guard isCurrentlyEmpty else {
            return .alreadyLoaded
        }

        // Use async stream for clean cancellation handling
        let result = await withTaskGroup(of: DocumentWaitResult.self) { group in
            // Task 1: Wait for callback
            group.addTask { @MainActor in
                await withCheckedContinuation { continuation in
                    setLoadCallback {
                        continuation.resume(returning: .loaded)
                    }
                }
            }

            // Task 2: Timeout
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timeout
            }

            // Return first result (loaded or timeout)
            let result = await group.next() ?? .timeout
            group.cancelAll()
            return result
        }

        // Clear callback regardless of result
        clearLoadCallback()
        return result
    }
}
