import Foundation

// MARK: - Chat Input Validator

/// Validates chat input and manages message history.
/// Extracted from ChatView for testability.
struct ChatInputValidator {

    // MARK: - Validation Error

    /// Errors that can occur during input validation.
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

    // MARK: - Validation

    /// Validates and trims user input.
    /// - Parameter input: Raw user input
    /// - Returns: Success with trimmed input, or failure with validation error
    static func validate(_ input: String) -> Result<String, ValidationError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for empty input
        if trimmed.isEmpty {
            return .failure(.empty)
        }

        // Check length limit
        if trimmed.count > ChatConfiguration.maxInputLength {
            return .failure(.tooLong(max: ChatConfiguration.maxInputLength))
        }

        return .success(trimmed)
    }

    // MARK: - History Management

    /// Trims message history to fit within a maximum count.
    /// Keeps the most recent messages.
    /// - Parameters:
    ///   - messages: Current message array
    ///   - max: Maximum number of messages to keep
    /// - Returns: Trimmed message array
    static func trimHistory<T>(_ messages: [T], max: Int) -> [T] {
        guard messages.count > max else {
            return messages
        }
        return Array(messages.suffix(max))
    }
}
