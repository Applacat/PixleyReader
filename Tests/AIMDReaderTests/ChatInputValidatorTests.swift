import XCTest

// MARK: - Test-Only Type Definition
// Since ChatInputValidator is in the main app (executable target),
// we mirror the implementation here for testing the logic.

/// Test version of ChatInputValidator.
/// Production source: Sources/Services/ChatInputValidator.swift
private struct TestableChatInputValidator {

    enum ValidationError: Error, Equatable {
        case empty
        case tooLong(max: Int)

        var localizedDescription: String {
            switch self {
            case .empty:
                return "Message cannot be empty."
            case .tooLong(let max):
                return "Your question is too long. Please keep questions under \(max) characters."
            }
        }
    }

    /// Must match ChatConfiguration.maxInputLength in production.
    /// Production source: Sources/Models/ChatConfiguration.swift
    /// If production changes this value, update here too.
    static let maxInputLength = 2000

    static func validate(_ input: String) -> Result<String, ValidationError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .failure(.empty)
        }

        if trimmed.count > maxInputLength {
            return .failure(.tooLong(max: maxInputLength))
        }

        return .success(trimmed)
    }

    static func trimHistory<T>(_ messages: [T], max: Int) -> [T] {
        guard messages.count > max else {
            return messages
        }
        return Array(messages.suffix(max))
    }
}

// MARK: - Tests

final class ChatInputValidatorTests: XCTestCase {

    // MARK: - Validation Tests

    func testValidate_emptyInput_returnsEmptyError() {
        // Given: Empty string
        let input = ""

        // When: Validate
        let result = TestableChatInputValidator.validate(input)

        // Then: Returns empty error
        switch result {
        case .failure(.empty):
            break // Expected
        default:
            XCTFail("Expected empty error, got \(result)")
        }
    }

    func testValidate_whitespaceOnlyInput_returnsEmptyError() {
        // Given: Whitespace-only input
        let input = "   \t\n   "

        // When: Validate
        let result = TestableChatInputValidator.validate(input)

        // Then: Returns empty error
        switch result {
        case .failure(.empty):
            break // Expected
        default:
            XCTFail("Expected empty error, got \(result)")
        }
    }

    func testValidate_validInput_returnsSuccess() {
        // Given: Valid input
        let input = "What is this document about?"

        // When: Validate
        let result = TestableChatInputValidator.validate(input)

        // Then: Returns success with input
        switch result {
        case .success(let trimmed):
            XCTAssertEqual(trimmed, input)
        default:
            XCTFail("Expected success, got \(result)")
        }
    }

    func testValidate_inputWithLeadingTrailingWhitespace_returnsTrimmed() {
        // Given: Input with whitespace
        let input = "   Hello world   "

        // When: Validate
        let result = TestableChatInputValidator.validate(input)

        // Then: Returns trimmed input
        switch result {
        case .success(let trimmed):
            XCTAssertEqual(trimmed, "Hello world")
        default:
            XCTFail("Expected success, got \(result)")
        }
    }

    func testValidate_inputExactlyAtLimit_returnsSuccess() {
        // Given: Input exactly at max length
        let input = String(repeating: "a", count: TestableChatInputValidator.maxInputLength)

        // When: Validate
        let result = TestableChatInputValidator.validate(input)

        // Then: Returns success
        switch result {
        case .success(let trimmed):
            XCTAssertEqual(trimmed.count, TestableChatInputValidator.maxInputLength)
        default:
            XCTFail("Expected success, got \(result)")
        }
    }

    func testValidate_inputOverLimit_returnsTooLongError() {
        // Given: Input over max length
        let input = String(repeating: "a", count: TestableChatInputValidator.maxInputLength + 1)

        // When: Validate
        let result = TestableChatInputValidator.validate(input)

        // Then: Returns too long error
        switch result {
        case .failure(.tooLong(let max)):
            XCTAssertEqual(max, TestableChatInputValidator.maxInputLength)
        default:
            XCTFail("Expected tooLong error, got \(result)")
        }
    }

    func testValidate_inputWithNewlines_returnsTrimmed() {
        // Given: Input with newlines
        let input = "\n\nHello\nWorld\n\n"

        // When: Validate
        let result = TestableChatInputValidator.validate(input)

        // Then: Returns trimmed (only leading/trailing whitespace)
        switch result {
        case .success(let trimmed):
            XCTAssertEqual(trimmed, "Hello\nWorld")
        default:
            XCTFail("Expected success, got \(result)")
        }
    }

    // MARK: - Trim History Tests

    func testTrimHistory_underLimit_returnsOriginal() {
        // Given: Messages under limit
        let messages = ["a", "b", "c"]
        let max = 5

        // When: Trim
        let result = TestableChatInputValidator.trimHistory(messages, max: max)

        // Then: Returns original
        XCTAssertEqual(result, messages)
    }

    func testTrimHistory_atLimit_returnsOriginal() {
        // Given: Messages exactly at limit
        let messages = ["a", "b", "c", "d", "e"]
        let max = 5

        // When: Trim
        let result = TestableChatInputValidator.trimHistory(messages, max: max)

        // Then: Returns original
        XCTAssertEqual(result, messages)
    }

    func testTrimHistory_overLimit_returnsMostRecent() {
        // Given: Messages over limit
        let messages = ["a", "b", "c", "d", "e", "f"]
        let max = 3

        // When: Trim
        let result = TestableChatInputValidator.trimHistory(messages, max: max)

        // Then: Returns most recent
        XCTAssertEqual(result, ["d", "e", "f"])
    }

    func testTrimHistory_emptyArray_returnsEmpty() {
        // Given: Empty array
        let messages: [String] = []
        let max = 5

        // When: Trim
        let result = TestableChatInputValidator.trimHistory(messages, max: max)

        // Then: Returns empty
        XCTAssertTrue(result.isEmpty)
    }

    func testTrimHistory_maxZero_returnsEmpty() {
        // Given: Max of zero
        let messages = ["a", "b", "c"]
        let max = 0

        // When: Trim
        let result = TestableChatInputValidator.trimHistory(messages, max: max)

        // Then: Returns empty
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Error Description Tests

    func testValidationError_emptyDescription() {
        // Given: Empty error
        let error = TestableChatInputValidator.ValidationError.empty

        // Then: Has appropriate description
        XCTAssertEqual(error.localizedDescription, "Message cannot be empty.")
    }

    func testValidationError_tooLongDescription() {
        // Given: Too long error
        let error = TestableChatInputValidator.ValidationError.tooLong(max: 2000)

        // Then: Has appropriate description with max value
        XCTAssertTrue(error.localizedDescription.contains("2000"))
    }
}
