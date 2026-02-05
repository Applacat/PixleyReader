import Foundation
import Markdown

/// Wrapper around swift-markdown's Document providing convenient access to parsed content.
public struct MarkdownAST: Sendable {

    /// The underlying parsed markdown document (stored as markup string for Sendable compliance)
    private let sourceMarkdown: String

    /// All headings in the document
    public let headings: [HeadingInfo]

    /// All code blocks in the document
    public let codeBlocks: [CodeBlockInfo]

    /// All links in the document
    public let links: [LinkInfo]

    /// All paragraphs in the document
    public let paragraphs: [ParagraphInfo]

    /// Re-parse and get the document (use sparingly as this re-parses)
    public var document: Markdown.Document {
        Markdown.Document(parsing: sourceMarkdown)
    }

    /// Creates a MarkdownAST by parsing the given markdown string
    public init(parsing source: String) {
        self.sourceMarkdown = source
        let doc = Markdown.Document(parsing: source)

        var headings: [HeadingInfo] = []
        var codeBlocks: [CodeBlockInfo] = []
        var links: [LinkInfo] = []
        var paragraphs: [ParagraphInfo] = []

        // Walk the document to extract elements
        for block in doc.children {
            Self.extractElements(
                from: block,
                headings: &headings,
                codeBlocks: &codeBlocks,
                links: &links,
                paragraphs: &paragraphs
            )
        }

        self.headings = headings
        self.codeBlocks = codeBlocks
        self.links = links
        self.paragraphs = paragraphs
    }

    private static func extractElements(
        from markup: any Markup,
        headings: inout [HeadingInfo],
        codeBlocks: inout [CodeBlockInfo],
        links: inout [LinkInfo],
        paragraphs: inout [ParagraphInfo]
    ) {
        if let heading = markup as? Heading {
            let text = heading.plainText
            headings.append(HeadingInfo(
                level: heading.level,
                text: text,
                startLine: heading.range?.lowerBound.line,
                endLine: heading.range?.upperBound.line
            ))
        } else if let codeBlock = markup as? CodeBlock {
            codeBlocks.append(CodeBlockInfo(
                language: codeBlock.language,
                code: codeBlock.code,
                startLine: codeBlock.range?.lowerBound.line,
                endLine: codeBlock.range?.upperBound.line
            ))
        } else if let link = markup as? Markdown.Link {
            links.append(LinkInfo(
                destination: link.destination,
                title: link.title,
                text: link.plainText,
                startLine: link.range?.lowerBound.line
            ))
        } else if let paragraph = markup as? Paragraph {
            paragraphs.append(ParagraphInfo(
                text: paragraph.plainText,
                startLine: paragraph.range?.lowerBound.line,
                endLine: paragraph.range?.upperBound.line
            ))
        }

        // Recursively process children
        for child in markup.children {
            extractElements(
                from: child,
                headings: &headings,
                codeBlocks: &codeBlocks,
                links: &links,
                paragraphs: &paragraphs
            )
        }
    }
}

// MARK: - Element Info Types

/// Information about a heading in the document
public struct HeadingInfo: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let level: Int
    public let text: String
    public let startLine: Int?
    public let endLine: Int?

    public init(level: Int, text: String, startLine: Int? = nil, endLine: Int? = nil) {
        self.level = level
        self.text = text
        self.startLine = startLine
        self.endLine = endLine
    }
}

/// Information about a code block in the document
public struct CodeBlockInfo: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let language: String?
    public let code: String
    public let startLine: Int?
    public let endLine: Int?

    public init(language: String?, code: String, startLine: Int? = nil, endLine: Int? = nil) {
        self.language = language
        self.code = code
        self.startLine = startLine
        self.endLine = endLine
    }
}

/// Information about a link in the document
public struct LinkInfo: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let destination: String?
    public let title: String?
    public let text: String
    public let startLine: Int?

    public init(destination: String?, title: String?, text: String, startLine: Int? = nil) {
        self.destination = destination
        self.title = title
        self.text = text
        self.startLine = startLine
    }
}

/// Information about a paragraph in the document
public struct ParagraphInfo: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let text: String
    public let startLine: Int?
    public let endLine: Int?

    public init(text: String, startLine: Int? = nil, endLine: Int? = nil) {
        self.text = text
        self.startLine = startLine
        self.endLine = endLine
    }
}
