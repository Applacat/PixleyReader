import Foundation
import FoundationModels

// MARK: - Pixley Intent Contract

/// The contract Pixley must fulfill when interpreting user requests.
/// Covers navigation, file operations, and questions.
@Generable(description: "Pixley's interpretation of what the user wants to do")
struct PixleyIntent {

    @Guide(description: "The primary action type")
    @Guide(.anyOf([
        "navigate",      // Open a folder
        "summarize",     // Summarize a file or folder contents
        "find",          // Find files matching criteria
        "answer",        // Answer a question about content
        "unknown"        // Could not determine intent
    ]))
    let action: String

    @Guide(description: "Target location - folder type or path")
    @Guide(.anyOf(["home", "documents", "downloads", "desktop", "custom", "none"]))
    let targetType: String

    @Guide(description: "Custom path if targetType is 'custom', otherwise empty")
    let customPath: String

    @Guide(description: "Search or filter query if action is 'find' or 'summarize'")
    let query: String

    @Guide(description: "Brief explanation of what Pixley understood")
    let interpretation: String
}

// MARK: - Pixley Response

/// Pixley's response after processing an intent.
struct PixleyResponse {
    let intent: PixleyIntent
    let message: String
    let shouldNavigate: Bool
    let targetURL: URL?
}
