import Foundation

// MARK: - App Error

/// Errors that can be displayed to the user via the status bar.
/// Designed for user-facing display, not for programmatic handling.
enum AppError: Equatable, Sendable {

    // MARK: - Error Types

    /// Warning level - yellow indicator, non-critical
    case warning(message: String)

    /// Error level - red indicator, critical
    case error(message: String)

    // MARK: - Properties

    /// User-facing message
    var message: String {
        switch self {
        case .warning(let message), .error(let message):
            return message
        }
    }

    /// Whether this is a warning (vs error)
    var isWarning: Bool {
        switch self {
        case .warning: return true
        case .error: return false
        }
    }

    // MARK: - Common Errors

    /// File exceeds maximum size limit
    static func fileTooLarge(sizeMB: Double) -> AppError {
        .error(message: String(format: "File too large (%.1f MB). Maximum is 10 MB.", sizeMB))
    }

    /// Text content exceeds size limit during editing
    static var textSizeExceeded: AppError {
        .warning(message: "Content exceeds size limit. Some features may be disabled.")
    }

    /// Generic file read error
    static func fileReadError(_ description: String) -> AppError {
        .error(message: "Unable to read file: \(description)")
    }
}
