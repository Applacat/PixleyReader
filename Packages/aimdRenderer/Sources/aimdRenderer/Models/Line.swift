import Foundation

/// Represents a single line in a document with its position and content.
public struct Line: Sendable, Equatable, Identifiable {

    /// Unique identifier for SwiftUI lists
    public var id: Int { number }

    /// 1-based line number
    public let number: Int

    /// Range of this line within the original document content
    public let range: Range<String.Index>

    /// The actual text content of the line (without newline)
    public let content: Substring

    /// Character count of the line
    public var length: Int {
        content.count
    }

    /// Whether the line is empty (whitespace only)
    public var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public init(number: Int, range: Range<String.Index>, content: Substring) {
        self.number = number
        self.range = range
        self.content = content
    }
}

extension Line: CustomStringConvertible {
    public var description: String {
        "\(number): \(content)"
    }
}
