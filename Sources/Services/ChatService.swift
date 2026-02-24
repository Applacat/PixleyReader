import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os.log

// MARK: - Chat Service

/// Service for AI chat functionality using Apple Foundation Models.
///
/// Foundation Models is stateful — LanguageModelSession maintains its own
/// transcript internally. Document context goes in `instructions` once,
/// and questions are sent via `respond(to:)`.
///
/// Crash prevention strategy:
/// 1. Catch ALL GenerationError types (context exceeded, guardrail, language)
/// 2. Timeout — races respond() against a sleep; if sleep wins, the respond task
///    is cancelled and the session is reset
/// 3. Fresh session per conversation — never reuse across "Forget" resets
/// 4. 3-turn auto-reset — after 3 Q&A turns, create fresh session
/// 5. Document truncation — cap at ~2500 chars to leave headroom
@available(macOS 26, *)
@MainActor
final class ChatService {

    private static let log = Logger(subsystem: "com.aimd.reader", category: "ChatService")

    // MARK: - Properties

    private var session: LanguageModelSession?

    /// Number of completed Q&A round-trips in this session
    private(set) var turnCount = 0

    /// Whether the last response triggered an auto-reset
    private(set) var didAutoReset = false

    /// The document content used to initialize the current session
    private var currentDocumentContent: String = ""

    // MARK: - Session Management

    /// Creates a fresh session with document context baked into instructions.
    func startSession(documentContent: String) {
        let truncated = String(documentContent.prefix(ChatConfiguration.maxDocumentChars))
        currentDocumentContent = truncated

        session = LanguageModelSession(instructions: """
            You are a helpful assistant analyzing a markdown document.
            Answer questions about the document concisely and accurately.
            If the answer is not in the document, say so.

            Document content:
            ---
            \(truncated)
            ---
            """)
        turnCount = 0
        didAutoReset = false
        Self.log.info("Session started with \(truncated.count) chars of document content")
    }

    /// Resets the session completely (user pressed "Forget").
    func resetSession() {
        if turnCount > 0 {
            Self.log.info("Session reset after \(self.turnCount) turns")
        }
        session = nil
        turnCount = 0
        didAutoReset = false
        currentDocumentContent = ""
    }

    // MARK: - Ask Question

    /// Sends a question to Foundation Models and returns the full response.
    ///
    /// Plain text `respond(to:)` does not support token streaming —
    /// the caller should show a "Thinking..." indicator while awaiting.
    ///
    /// Includes a built-in timeout: if `respond(to:)` doesn't return within
    /// `ChatConfiguration.responseTimeout`, the call is cancelled, the session
    /// is reset, and an error result is returned.
    ///
    /// Returns a `ChatResult` indicating success, auto-reset, or error.
    func ask(question: String, documentContent: String) async -> ChatResult {
        didAutoReset = false

        // Ensure session exists (auto-create if needed)
        if session == nil {
            startSession(documentContent: documentContent)
        }

        // Check if we need auto-reset before this turn
        if turnCount >= ChatConfiguration.maxTurnsBeforeReset {
            Self.log.info("Auto-reset: turn limit reached (\(self.turnCount) turns)")
            startSession(documentContent: documentContent)
            didAutoReset = true
        }

        guard let session else {
            return .error("Session could not be created.")
        }

        Self.log.info("Asking question: turn=\(self.turnCount + 1), question=\(question.prefix(80), privacy: .private)")

        // Capture session reference to local before crossing Task boundary.
        // Defensive against future Sendable enforcement on LanguageModelSession.
        let capturedSession = session

        // Race respond() vs timeout.
        // The respond task extracts .content (String) so only Sendable types cross
        // the task boundary — Response<String> stays inside the task.
        let respondTask = Task<String, Error> {
            let response = try await capturedSession.respond(to: question)
            return response.content
        }

        let watchdog = Task {
            try await Task.sleep(for: ChatConfiguration.responseTimeout)
            respondTask.cancel()
        }

        do {
            let content = try await respondTask.value
            watchdog.cancel()

            turnCount += 1
            Self.log.info("Response received: \(content.count) chars, turn=\(self.turnCount)")

            if didAutoReset {
                return .successWithReset(content)
            }
            return .success(content)
        } catch let error as LanguageModelSession.GenerationError {
            watchdog.cancel()
            return handleGenerationError(error, documentContent: documentContent)
        } catch is CancellationError {
            watchdog.cancel()
            // If the respondTask was cancelled, the watchdog fired (timeout)
            if respondTask.isCancelled {
                Self.log.error("Response timed out after \(ChatConfiguration.responseTimeout)")
                startSession(documentContent: documentContent)
                return .error("The AI took too long to respond. The conversation has been reset — please try again.")
            }
            return .cancelled
        } catch {
            watchdog.cancel()
            Self.log.error("Unexpected error: \(error.localizedDescription)")
            return .error("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Handling

    private func handleGenerationError(
        _ error: LanguageModelSession.GenerationError,
        documentContent: String
    ) -> ChatResult {
        switch error {
        case .exceededContextWindowSize:
            Self.log.warning("Context window exceeded at turn \(self.turnCount)")
            startSession(documentContent: documentContent)
            return .error("Context limit reached. The conversation has been reset — please ask your question again.")

        case .guardrailViolation:
            Self.log.warning("Guardrail violation")
            return .error("I can't respond to that question. Please try rephrasing.")

        case .unsupportedLanguageOrLocale:
            Self.log.warning("Unsupported language/locale")
            return .error("This language isn't supported by on-device AI. Please try asking in English.")

        default:
            Self.log.error("Unknown GenerationError: \(String(describing: error))")
            startSession(documentContent: documentContent)
            return .error("An unexpected AI error occurred. The conversation has been reset.")
        }
    }
}

// MARK: - Chat Result

/// Result of a chat request, covering all outcomes.
@available(macOS 26, *)
enum ChatResult {
    /// Successful response
    case success(String)
    /// Successful response, but session was auto-reset first
    case successWithReset(String)
    /// Error message to display to user
    case error(String)
    /// Request was cancelled
    case cancelled
}
