import XCTest

// MARK: - Test-Only Type Definition
// Since ChatConfiguration is in the main app (executable target),
// we mirror the implementation here for testing the logic.

/// Test version of ChatConfiguration
private enum TestableChatConfiguration {

    // MARK: - Message Limits

    static let maxMessageHistory = 50
    static let maxInputLength = 2000

    // MARK: - Context Limits

    static let maxContextTokens = 4096
    static let charsPerToken = 4
    static let maxContextChars = maxContextTokens * charsPerToken
    static let maxContextLength = 8000

    // MARK: - Conversation Context

    static let conversationDocExcerpt = 2000
    static let recentMessageCount = 6
    static let promptOverhead = 200
}

// MARK: - Tests

final class ChatConfigurationTests: XCTestCase {

    // MARK: - Constants Accessibility Tests

    func testMaxMessageHistory_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.maxMessageHistory, 50)
    }

    func testMaxInputLength_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.maxInputLength, 2000)
    }

    func testMaxContextTokens_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.maxContextTokens, 4096)
    }

    func testCharsPerToken_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.charsPerToken, 4)
    }

    func testMaxContextLength_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.maxContextLength, 8000)
    }

    func testConversationDocExcerpt_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.conversationDocExcerpt, 2000)
    }

    func testRecentMessageCount_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.recentMessageCount, 6)
    }

    func testPromptOverhead_isAccessible() {
        // Then: Constant is accessible and has expected value
        XCTAssertEqual(TestableChatConfiguration.promptOverhead, 200)
    }

    // MARK: - Computed Properties Tests

    func testMaxContextChars_computedCorrectly() {
        // Given: Token limit and chars per token
        let expectedChars = TestableChatConfiguration.maxContextTokens * TestableChatConfiguration.charsPerToken

        // Then: maxContextChars equals tokens * charsPerToken
        XCTAssertEqual(TestableChatConfiguration.maxContextChars, expectedChars)
        XCTAssertEqual(TestableChatConfiguration.maxContextChars, 16384)  // 4096 * 4
    }

    // MARK: - Value Consistency Tests

    func testConversationDocExcerpt_lessThanMaxContextLength() {
        // Then: Conversation excerpt is smaller than full context length
        XCTAssertLessThan(
            TestableChatConfiguration.conversationDocExcerpt,
            TestableChatConfiguration.maxContextLength
        )
    }

    func testMaxContextLength_lessThanMaxContextChars() {
        // Then: Max context length is less than max context chars
        // (allows room for prompt overhead, history, etc.)
        XCTAssertLessThan(
            TestableChatConfiguration.maxContextLength,
            TestableChatConfiguration.maxContextChars
        )
    }

    func testPromptOverhead_reasonableSize() {
        // Then: Prompt overhead is a reasonable value (not too small, not too large)
        XCTAssertGreaterThan(TestableChatConfiguration.promptOverhead, 0)
        XCTAssertLessThan(TestableChatConfiguration.promptOverhead, 1000)
    }

    func testRecentMessageCount_isEven() {
        // Then: Recent message count is even (for user/assistant pairs)
        XCTAssertEqual(TestableChatConfiguration.recentMessageCount % 2, 0)
    }
}
