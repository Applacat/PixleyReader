import Foundation

// MARK: - Chat Configuration

/// Centralized configuration constants for chat functionality.
/// Consolidates scattered constants from ChatView, ChatService, and ChatInputValidator.
enum ChatConfiguration {

    // MARK: - Message Limits

    /// Maximum number of messages to keep in chat history
    static let maxMessageHistory = 50

    /// Maximum allowed input length (characters) for user questions
    static let maxInputLength = 2000

    // MARK: - Context Limits

    /// Approximate token limit for AI context
    static let maxContextTokens = 4096

    /// Estimated characters per token (rough approximation)
    static let charsPerToken = 4

    /// Maximum characters for context window (computed from tokens)
    static let maxContextChars = maxContextTokens * charsPerToken  // ~16K chars

    /// Maximum document length before truncation
    static let maxContextLength = 8000

    // MARK: - Conversation Context

    /// Character limit for document excerpt in conversation mode
    static let conversationDocExcerpt = 2000

    /// Number of recent messages to include in follow-up prompts
    static let recentMessageCount = 6

    /// Overhead characters for prompt structure
    static let promptOverhead = 200
}
