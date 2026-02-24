import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// ChatService uses FoundationModels (@available(macOS 26, *)) which we can't import in tests.
// We mirror the state machine logic: turn counting, auto-reset, session lifecycle, error mapping.

// MARK: - ChatResult Mirror

private enum TestableChatResult: Equatable {
    case success(String)
    case successWithReset(String)
    case error(String)
    case cancelled
}

// MARK: - ChatConfiguration Mirror

private enum TestableChatConfiguration {
    static let maxTurnsBeforeReset = 3
    static let responseTimeoutSeconds: Double = 30
    static let maxDocumentChars = 2500
}

// MARK: - GenerationError Mirror

private enum TestableGenerationError: Error {
    case exceededContextWindowSize
    case guardrailViolation
    case unsupportedLanguageOrLocale
}

// MARK: - ChatService Mirror

/// Mirrors ChatService state machine logic without FoundationModels dependency.
/// The respond closure simulates LanguageModelSession.respond(to:).
/// Note: Production ChatService is @MainActor, but the test mirror omits it
/// to avoid actor-isolation complexities in setUp — we're testing logic, not concurrency.
private final class TestableChatService {

    private(set) var turnCount = 0
    private(set) var didAutoReset = false
    private var hasSession = false
    private var currentDocumentContent: String = ""

    /// Injectable respond closure — simulates LanguageModelSession.respond(to:)
    var respondHandler: ((String) async throws -> String)?

    func startSession(documentContent: String) {
        let truncated = String(documentContent.prefix(TestableChatConfiguration.maxDocumentChars))
        currentDocumentContent = truncated
        hasSession = true
        turnCount = 0
        didAutoReset = false
    }

    func resetSession() {
        hasSession = false
        turnCount = 0
        didAutoReset = false
        currentDocumentContent = ""
    }

    func ask(question: String, documentContent: String) async -> TestableChatResult {
        didAutoReset = false

        // Ensure session exists (auto-create if needed)
        if !hasSession {
            startSession(documentContent: documentContent)
        }

        // Check if we need auto-reset before this turn
        if turnCount >= TestableChatConfiguration.maxTurnsBeforeReset {
            startSession(documentContent: documentContent)
            didAutoReset = true
        }

        guard hasSession else {
            return .error("Session could not be created.")
        }

        guard let respondHandler else {
            return .error("No respond handler configured.")
        }

        do {
            let content = try await respondHandler(question)
            turnCount += 1

            if didAutoReset {
                return .successWithReset(content)
            }
            return .success(content)
        } catch let error as TestableGenerationError {
            return handleGenerationError(error, documentContent: documentContent)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .error("Error: \(error.localizedDescription)")
        }
    }

    private func handleGenerationError(
        _ error: TestableGenerationError,
        documentContent: String
    ) -> TestableChatResult {
        switch error {
        case .exceededContextWindowSize:
            startSession(documentContent: documentContent)
            return .error("Context limit reached. The conversation has been reset — please ask your question again.")

        case .guardrailViolation:
            return .error("I can't respond to that question. Please try rephrasing.")

        case .unsupportedLanguageOrLocale:
            return .error("This language isn't supported by on-device AI. Please try asking in English.")
        }
    }
}

// MARK: - Tests

final class ChatServiceTests: XCTestCase {

    private var service: TestableChatService!

    override func setUp() {
        service = TestableChatService()
        service.respondHandler = { question in
            return "Response to: \(question)"
        }
    }

    override func tearDown() {
        service = nil
    }

    // MARK: - Session Lifecycle

    func testStartSession_resetsTurnCount() {
        service.startSession(documentContent: "doc")
        XCTAssertEqual(service.turnCount, 0)
        XCTAssertFalse(service.didAutoReset)
    }

    func testResetSession_nilsSessionAndZerosTurnCount() async {
        // Given: Active session with turns
        _ = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 1)

        // When: Reset
        service.resetSession()

        // Then: All state cleared
        XCTAssertEqual(service.turnCount, 0)
        XCTAssertFalse(service.didAutoReset)
    }

    // MARK: - Auto-create Session

    func testAsk_withNoSession_autoCreates() async {
        // Given: No explicit startSession call
        service.resetSession()

        // When: Ask creates session automatically
        let result = await service.ask(question: "Q1", documentContent: "doc content")

        // Then: Succeeds (session was auto-created)
        if case .success(let response) = result {
            XCTAssertTrue(response.contains("Q1"))
        } else {
            XCTFail("Expected .success, got \(result)")
        }
    }

    // MARK: - Turn Counting

    func testAsk_incrementsTurnCount() async {
        service.startSession(documentContent: "doc")
        XCTAssertEqual(service.turnCount, 0)

        _ = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 1)

        _ = await service.ask(question: "Q2", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 2)

        _ = await service.ask(question: "Q3", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 3)
    }

    // MARK: - Auto-Reset

    func testAsk_atTurnLimit_triggersAutoReset() async {
        service.startSession(documentContent: "doc")

        // Use up all turns
        for i in 1...TestableChatConfiguration.maxTurnsBeforeReset {
            _ = await service.ask(question: "Q\(i)", documentContent: "doc")
        }
        XCTAssertEqual(service.turnCount, 3)

        // Next ask should trigger auto-reset
        _ = await service.ask(question: "Q4", documentContent: "doc")
        XCTAssertTrue(service.didAutoReset)
        // turnCount is 1 (reset to 0, then incremented by successful response)
        XCTAssertEqual(service.turnCount, 1)
    }

    func testAutoReset_returnsSuccessWithReset() async {
        service.startSession(documentContent: "doc")

        // Exhaust turns
        for i in 1...TestableChatConfiguration.maxTurnsBeforeReset {
            _ = await service.ask(question: "Q\(i)", documentContent: "doc")
        }

        // Next ask triggers auto-reset
        let result = await service.ask(question: "Q4", documentContent: "doc")
        if case .successWithReset = result {
            // Expected
        } else {
            XCTFail("Expected .successWithReset, got \(result)")
        }
    }

    func testNormalResponse_returnsSuccess() async {
        service.startSession(documentContent: "doc")
        let result = await service.ask(question: "Q1", documentContent: "doc")
        if case .success(let response) = result {
            XCTAssertTrue(response.contains("Q1"))
        } else {
            XCTFail("Expected .success, got \(result)")
        }
        XCTAssertFalse(service.didAutoReset)
    }

    // MARK: - Error Handling

    func testError_contextExceeded_resetsSession() async {
        service.startSession(documentContent: "doc")
        service.respondHandler = { _ in
            throw TestableGenerationError.exceededContextWindowSize
        }

        let result = await service.ask(question: "Q1", documentContent: "doc")
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("Context limit"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
        // Session was reset (turnCount back to 0)
        XCTAssertEqual(service.turnCount, 0)
    }

    func testError_guardrailViolation_doesNotResetSession() async {
        service.startSession(documentContent: "doc")
        _ = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 1)

        // Reconfigure to throw guardrail
        service.respondHandler = { _ in
            throw TestableGenerationError.guardrailViolation
        }

        let result = await service.ask(question: "bad question", documentContent: "doc")
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("can't respond"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
        // Session NOT reset — turnCount still 1
        XCTAssertEqual(service.turnCount, 1)
    }

    func testError_unsupportedLanguage_returnsError() async {
        service.startSession(documentContent: "doc")
        service.respondHandler = { _ in
            throw TestableGenerationError.unsupportedLanguageOrLocale
        }

        let result = await service.ask(question: "Q1", documentContent: "doc")
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("language isn't supported"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
    }

    // MARK: - Cancellation

    func testCancellation_returnsCancelled() async {
        service.startSession(documentContent: "doc")
        service.respondHandler = { _ in
            throw CancellationError()
        }

        let result = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(result, .cancelled)
    }
}
