import Foundation

/// Represents a parsed markdown document with both line-based and AST-based access.
///
/// DocumentModel provides two complementary views of a markdown document:
/// 1. Line-based: For search, bookmarks, line numbers, and progress tracking
/// 2. AST-based: For semantic operations like heading navigation and structured rendering
public struct DocumentModel: Sendable {

    /// The original markdown content
    public let content: String

    /// Lines in the document with their positions
    public let lines: [Line]

    /// Parsed AST for semantic access
    public let ast: MarkdownAST

    /// Number of lines in the document
    public var lineCount: Int {
        lines.count
    }

    /// Whether the document is empty
    public var isEmpty: Bool {
        content.isEmpty
    }

    /// Creates a DocumentModel from markdown content
    public init(content: String) {
        self.content = content
        self.lines = Self.parseLines(from: content)
        self.ast = MarkdownAST(parsing: content)
    }

    /// Creates an empty DocumentModel
    public init() {
        self.content = ""
        self.lines = []
        self.ast = MarkdownAST(parsing: "")
    }

    // MARK: - Line Access

    /// Returns the line at the given 1-based line number
    public func line(at number: Int) -> Line? {
        guard number >= 1 && number <= lines.count else { return nil }
        return lines[number - 1]
    }

    /// Returns lines in the given range (1-based, inclusive)
    public func lines(from start: Int, to end: Int) -> [Line] {
        let safeStart = max(1, start)
        let safeEnd = min(lines.count, end)
        guard safeStart <= safeEnd else { return [] }
        return Array(lines[(safeStart - 1)...(safeEnd - 1)])
    }

    /// Finds the line number containing the given string index
    public func lineNumber(containing index: String.Index) -> Int? {
        for line in lines {
            if line.range.contains(index) || line.range.upperBound == index {
                return line.number
            }
        }
        return nil
    }

    // MARK: - Search

    /// Finds all occurrences of the search term in the document
    public func search(for term: String, caseSensitive: Bool = false) -> [SearchMatch] {
        guard !term.isEmpty else { return [] }

        var matches: [SearchMatch] = []
        let searchContent = caseSensitive ? content : content.lowercased()
        let searchTerm = caseSensitive ? term : term.lowercased()

        var searchStart = searchContent.startIndex
        while let range = searchContent.range(of: searchTerm, range: searchStart..<searchContent.endIndex) {
            // Map back to original content indices
            let originalRange = content.index(content.startIndex, offsetBy: searchContent.distance(from: searchContent.startIndex, to: range.lowerBound))..<content.index(content.startIndex, offsetBy: searchContent.distance(from: searchContent.startIndex, to: range.upperBound))

            if let lineNum = lineNumber(containing: originalRange.lowerBound) {
                matches.append(SearchMatch(
                    range: originalRange,
                    lineNumber: lineNum,
                    matchedText: String(content[originalRange])
                ))
            }
            searchStart = range.upperBound
        }

        return matches
    }

    // MARK: - Private Helpers

    private static func parseLines(from content: String) -> [Line] {
        guard !content.isEmpty else { return [] }

        var lines: [Line] = []
        var lineNumber = 1
        var currentIndex = content.startIndex

        while currentIndex < content.endIndex {
            let lineStart = currentIndex

            // Find end of line (newline or end of string)
            if let newlineRange = content.range(of: "\n", range: currentIndex..<content.endIndex) {
                let lineEnd = newlineRange.lowerBound
                let lineContent = content[lineStart..<lineEnd]
                lines.append(Line(
                    number: lineNumber,
                    range: lineStart..<newlineRange.upperBound,
                    content: lineContent
                ))
                currentIndex = newlineRange.upperBound
            } else {
                // Last line without trailing newline
                let lineContent = content[lineStart..<content.endIndex]
                lines.append(Line(
                    number: lineNumber,
                    range: lineStart..<content.endIndex,
                    content: lineContent
                ))
                currentIndex = content.endIndex
            }

            lineNumber += 1
        }

        return lines
    }
}

// MARK: - Search Match

/// Represents a search match within the document
public struct SearchMatch: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let range: Range<String.Index>
    public let lineNumber: Int
    public let matchedText: String

    public init(range: Range<String.Index>, lineNumber: Int, matchedText: String) {
        self.range = range
        self.lineNumber = lineNumber
        self.matchedText = matchedText
    }
}
