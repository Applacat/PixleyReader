import Foundation

// MARK: - Markdown Theme Protocol

/// Protocol defining a pluggable renderer for markdown content.
/// Themes transform markdown elements into their target Output type.
///
/// OOD: Pure transformation protocol - no state, just input → output.
/// Each theme implementation produces its own Output type (SwiftUI View, HTML String, PDF Data, etc.)
///
/// Note: MainActor isolation allows SwiftUI theme implementations while
/// non-UI themes (HTML, PDF) can use nonisolated conformances.
@MainActor
public protocol MarkdownTheme {
    /// The output type this theme produces
    associatedtype Output

    /// Configuration for rendering
    var configuration: ThemeConfiguration { get }

    // MARK: - Block Renderers

    /// Renders a heading element
    func render(heading: HeadingInfo) -> Output

    /// Renders a paragraph element
    func render(paragraph: ParagraphInfo) -> Output

    /// Renders a code block element
    func render(codeBlock: CodeBlockInfo) -> Output

    /// Renders a link element
    func render(link: LinkInfo) -> Output

    /// Renders a list item
    func render(listItem: String, ordered: Bool, index: Int?) -> Output

    /// Renders a block quote
    func render(blockQuote: String) -> Output

    /// Renders a horizontal rule / thematic break
    func renderThematicBreak() -> Output

    /// Renders an image
    func render(image: ImageInfo) -> Output

    /// Renders inline code
    func render(inlineCode: String) -> Output

    /// Renders emphasis (italic)
    func render(emphasis: String) -> Output

    /// Renders strong (bold)
    func render(strong: String) -> Output

    /// Renders strikethrough text
    func render(strikethrough: String) -> Output

    // MARK: - Full Document Rendering

    /// Renders a complete document model
    func render(document: DocumentModel) -> Output
}

// MARK: - Theme Configuration

/// Configuration options for theme rendering
public struct ThemeConfiguration: Sendable {
    /// Font size in points
    public var fontSize: CGFloat

    /// Font family name (nil = system default)
    public var fontFamily: String?

    /// Color scheme for syntax highlighting
    public var syntaxTheme: SyntaxTheme

    /// Heading size scale factor
    public var headingScale: HeadingScale

    /// Whether to show line numbers
    public var showLineNumbers: Bool

    /// Whether to underline links
    public var underlineLinks: Bool

    public init(
        fontSize: CGFloat = 14,
        fontFamily: String? = nil,
        syntaxTheme: SyntaxTheme = .xcodeDark,
        headingScale: HeadingScale = .normal,
        showLineNumbers: Bool = false,
        underlineLinks: Bool = true
    ) {
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.syntaxTheme = syntaxTheme
        self.headingScale = headingScale
        self.showLineNumbers = showLineNumbers
        self.underlineLinks = underlineLinks
    }
}

// MARK: - Heading Scale

/// Scale factors for heading sizes
public enum HeadingScale: String, Sendable, CaseIterable {
    case compact
    case normal
    case spacious

    /// Returns the scale factor for a heading level (1-6)
    public func factor(for level: Int) -> CGFloat {
        let baseFactor: CGFloat
        switch self {
        case .compact:
            baseFactor = 1.2
        case .normal:
            baseFactor = 1.4
        case .spacious:
            baseFactor = 1.6
        }
        // Level 1 = largest, level 6 = smallest
        let levelFactor = max(1.0, baseFactor - (CGFloat(level - 1) * 0.15))
        return levelFactor
    }
}

// MARK: - Image Info

/// Information about an image in the document
public struct ImageInfo: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let source: String?
    public let title: String?
    public let altText: String

    public init(source: String?, title: String?, altText: String) {
        self.source = source
        self.title = title
        self.altText = altText
    }
}
