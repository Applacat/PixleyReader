import XCTest

// MARK: - Test-Only Type Definition
// Since ChatConfiguration is in the main app (executable target),
// we mirror the implementation here for testing the logic.
//
// IMPORTANT: This mirror must match production ChatConfiguration exactly.
// Production source: Sources/Models/ChatConfiguration.swift

/// Test version of ChatConfiguration — mirrors production values.
/// If production changes, update this mirror and these tests.
private enum TestableChatConfiguration {

    // MARK: - Message Limits

    /// Maximum number of messages to keep in chat history display
    static let maxMessageHistory = 50

    /// Maximum allowed input length (characters) for user questions
    static let maxInputLength = 2000

    // MARK: - Foundation Models Limits

    /// Maximum document characters to include in instructions (~800 tokens).
    /// Leaves headroom for conversation within the 4096-token context window.
    static let maxDocumentChars = 2500

    /// Auto-reset session after this many Q&A round-trips.
    /// Prevents context window exhaustion on long conversations.
    static let maxTurnsBeforeReset = 3

    /// Timeout for each Foundation Models respond() call (in seconds).
    /// Prevents app freeze if the model hangs.
    static let responseTimeoutSeconds: Double = 30
}

// MARK: - Tests

final class ChatConfigurationTests: XCTestCase {

    // MARK: - Value Consistency Tests

    func testMaxInputLength_isPositive() {
        XCTAssertGreaterThan(TestableChatConfiguration.maxInputLength, 0)
    }

    func testMaxDocumentChars_fitsContextWindow() {
        // Document chars (~800 tokens at ~3 chars/token) should leave room
        // in the 4096-token context window for conversation history.
        let estimatedDocTokens = TestableChatConfiguration.maxDocumentChars / 3
        XCTAssertLessThan(estimatedDocTokens, 4096,
            "Document char budget should leave room in the 4096-token context window")
    }

    func testMaxTurnsBeforeReset_isReasonable() {
        // Should be at least 1 (allow at least one exchange)
        // and not so large that context overflows
        XCTAssertGreaterThanOrEqual(TestableChatConfiguration.maxTurnsBeforeReset, 1)
        XCTAssertLessThanOrEqual(TestableChatConfiguration.maxTurnsBeforeReset, 20)
    }

    func testResponseTimeout_isReasonable() {
        // Should be long enough for model to respond, but not so long the user thinks it froze
        XCTAssertGreaterThanOrEqual(TestableChatConfiguration.responseTimeoutSeconds, 5)
        XCTAssertLessThanOrEqual(TestableChatConfiguration.responseTimeoutSeconds, 120)
    }

    func testMaxMessageHistory_isGreaterThanMaxTurns() {
        // Message history should accommodate more messages than the turn limit
        // (each turn = 2 messages: user + assistant)
        let messagesPerTurn = 2
        XCTAssertGreaterThan(
            TestableChatConfiguration.maxMessageHistory,
            TestableChatConfiguration.maxTurnsBeforeReset * messagesPerTurn
        )
    }
}
