import AppKit
import Foundation
import aimdRenderer

/// A focused Markdown highlighter with lazy-compiled patterns and debouncing support.
/// Core highlighting logic is nonisolated for testability; only debouncing requires @MainActor.
///
/// Uses aimdRenderer's SyntaxTheme system for consistent theming across the app.
final class MarkdownHighlighter {

    // MARK: - Theme (now powered by aimdRenderer)

    /// Converts aimdRenderer SyntaxPalette to NSColors for AppKit rendering
    struct Theme {
        let heading1: NSColor
        let heading2: NSColor
        let heading3: NSColor
        let bold: NSColor
        let italic: NSColor
        let code: NSColor
        let codeBackground: NSColor
        let link: NSColor
        let listMarker: NSColor
        let blockquote: NSColor
        let separator: NSColor
        let foreground: NSColor
        let background: NSColor

        /// Creates a Theme from an aimdRenderer SyntaxPalette
        init(from palette: SyntaxPalette) {
            self.heading1 = NSColor(hex: palette.type) ?? .systemBlue
            self.heading2 = NSColor(hex: palette.function) ?? .systemIndigo
            self.heading3 = NSColor(hex: palette.keyword) ?? .systemPurple
            self.bold = NSColor(hex: palette.foreground) ?? .labelColor
            self.italic = NSColor(hex: palette.foreground) ?? .labelColor
            self.code = NSColor(hex: palette.string) ?? .systemOrange
            self.codeBackground = (NSColor(hex: palette.selection) ?? .quaternaryLabelColor).withAlphaComponent(0.3)
            self.link = NSColor(hex: palette.function) ?? .systemTeal
            self.listMarker = NSColor(hex: palette.comment) ?? .systemGray
            self.blockquote = NSColor(hex: palette.comment) ?? .secondaryLabelColor
            self.separator = NSColor(hex: palette.lineNumber) ?? .separatorColor
            self.foreground = NSColor(hex: palette.foreground) ?? .labelColor
            self.background = NSColor(hex: palette.background) ?? .textBackgroundColor
        }

        /// Default theme using Xcode Dark palette
        static let `default` = Theme(from: SyntaxTheme.xcodeDark.palette)
    }

    // MARK: - Highlight Rules

    private enum HighlightRule {
        case heading
        case codeBlock
        case inlineCode
        case bold
        case italic
        case link
        case bareLink
        case listMarker
        case blockquote
        case separator
    }

    // MARK: - Heading Scale

    enum HeadingScale {
        case compact   // 1.1, 1.05, 1.0
        case normal    // 1.6, 1.4, 1.2
        case spacious  // 2.0, 1.7, 1.4

        var multipliers: (h1: CGFloat, h2: CGFloat, h3: CGFloat) {
            switch self {
            case .compact:  return (1.1, 1.05, 1.0)
            case .normal:   return (1.6, 1.4, 1.2)
            case .spacious: return (2.0, 1.7, 1.4)
            }
        }
    }

    // MARK: - Properties

    let theme: Theme
    let baseFont: NSFont
    let headingScale: HeadingScale

    /// Compiled patterns - created once, reused for every highlight call
    private let patterns: [(NSRegularExpression, HighlightRule)]

    // MARK: - Initialization

    init(theme: Theme = .default, fontSize: CGFloat = 14, fontFamily: String? = nil, headingScale: HeadingScale = .normal) {
        self.theme = theme
        self.headingScale = headingScale
        self.baseFont = Self.resolveFont(family: fontFamily, size: fontSize, weight: .regular)
        self.patterns = Self.compilePatterns()
    }

    /// Resolves a font from family name, using system font descriptors for Apple fonts.
    static func resolveFont(family: String?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        guard let family else {
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        switch family {
        case "New York":
            // Serif system font via descriptor
            let descriptor = NSFont.systemFont(ofSize: size, weight: weight)
                .fontDescriptor.withDesign(.serif)
            return descriptor.flatMap { NSFont(descriptor: $0, size: size) }
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        case "SF Pro":
            return NSFont.systemFont(ofSize: size, weight: weight)
        case "SF Mono":
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        default:
            // Try direct name lookup for third-party fonts
            return NSFont(name: family, size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    /// Convenience initializer using aimdRenderer's SyntaxTheme
    convenience init(syntaxTheme: SyntaxTheme, fontSize: CGFloat = 14, fontFamily: String? = nil, headingScale: HeadingScale = .normal) {
        self.init(theme: Theme(from: syntaxTheme.palette), fontSize: fontSize, fontFamily: fontFamily, headingScale: headingScale)
    }

    // MARK: - Pattern Compilation

    private static func compilePatterns() -> [(NSRegularExpression, HighlightRule)] {
        let definitions: [(String, HighlightRule)] = [
            (#"^(#{1,6})\s+(.+)$"#, .heading),
            (#"```[\s\S]*?```"#, .codeBlock),
            (#"`[^`\n]+`"#, .inlineCode),
            (#"\*\*(.+?)\*\*|__(.+?)__"#, .bold),
            (#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, .italic),
            (#"\[([^\]]+)\]\(([^\)]+)\)"#, .link),
            (#"(?<!\()https?://[^\s\]\)>]+"#, .bareLink),
            (#"^[\t ]*[-*+][\t ]"#, .listMarker),
            (#"^[\t ]*\d+\.[\t ]"#, .listMarker),
            (#"^>.*$"#, .blockquote),
            (#"^[-*_]{3,}$"#, .separator),
        ]

        return definitions.compactMap { pattern, rule in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                return nil
            }
            return (regex, rule)
        }
    }

    // MARK: - Highlighting (Core - Testable)

    /// Pure highlighting logic - no MainActor constraint for testability
    /// Security: Refuses to highlight files over 1MB to prevent regex DoS
    func highlight(_ text: String) -> NSAttributedString {
        // Security: Don't highlight extremely large files (prevents regex catastrophic backtracking)
        // Files over 1MB are shown as plain text with base styling
        guard text.utf8.count <= MarkdownConfig.maxHighlightSize else {
            return NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: theme.foreground
            ])
        }

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: theme.foreground
        ])

        let fullRange = NSRange(location: 0, length: attributed.length)

        for (regex, rule) in patterns {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                applyRule(rule, to: attributed, match: match)
            }
        }

        return attributed
    }

    private func applyRule(_ rule: HighlightRule, to str: NSMutableAttributedString, match: NSTextCheckingResult) {
        switch rule {
        case .heading:
            let hashCount = match.range(at: 1).length
            let m = headingScale.multipliers
            let color: NSColor
            let size: CGFloat
            switch hashCount {
            case 1: color = theme.heading1; size = baseFont.pointSize * m.h1
            case 2: color = theme.heading2; size = baseFont.pointSize * m.h2
            default: color = theme.heading3; size = baseFont.pointSize * m.h3
            }
            // Use the same font family as base, just scaled and bold
            let headingFont = baseFont.withSize(size).withWeight(.bold)
            str.addAttributes([
                .foregroundColor: color,
                .font: headingFont
            ], range: match.range)

        case .codeBlock:
            // Code blocks always use monospaced regardless of base font family
            str.addAttributes([
                .foregroundColor: theme.code,
                .backgroundColor: theme.codeBackground,
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            ], range: match.range)

        case .inlineCode:
            str.addAttributes([
                .foregroundColor: theme.code,
                .backgroundColor: theme.codeBackground
            ], range: match.range)

        case .bold:
            str.addAttribute(.font, value: baseFont.withWeight(.bold), range: match.range)

        case .italic:
            let italicFont = baseFont.withTraits(.italicFontMask)
            str.addAttribute(.font, value: italicFont, range: match.range)

        case .link:
            str.addAttribute(.foregroundColor, value: theme.link, range: match.range)
            // Make the link text (group 1) clickable using the URL (group 2)
            if match.numberOfRanges > 2 {
                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                if textRange.location != NSNotFound && urlRange.location != NSNotFound,
                   let swiftRange = Range(urlRange, in: str.string) {
                    let urlString = String(str.string[swiftRange])
                    if let url = URL(string: urlString) {
                        str.addAttribute(.link, value: url, range: textRange)
                    }
                }
            }

        case .bareLink:
            str.addAttribute(.foregroundColor, value: theme.link, range: match.range)
            if let swiftRange = Range(match.range, in: str.string) {
                let urlString = String(str.string[swiftRange])
                if let url = URL(string: urlString) {
                    str.addAttribute(.link, value: url, range: match.range)
                }
            }

        case .listMarker:
            str.addAttribute(.foregroundColor, value: theme.listMarker, range: match.range)

        case .blockquote:
            str.addAttribute(.foregroundColor, value: theme.blockquote, range: match.range)

        case .separator:
            str.addAttribute(.foregroundColor, value: theme.separator, range: match.range)
        }
    }
}

// MARK: - Debouncing Extension (MainActor)

/// Debouncing wrapper - only this part needs MainActor isolation
@MainActor
final class DebouncedHighlighter {

    let highlighter: MarkdownHighlighter  // Changed from private to internal
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: Duration

    init(highlighter: MarkdownHighlighter = MarkdownHighlighter(), debounceDelay: Duration = .milliseconds(100)) {
        self.highlighter = highlighter
        self.debounceDelay = debounceDelay
    }

    deinit {
        debounceTask?.cancel()
    }

    /// Debounced highlighting - call this from text change handlers
    func highlightDebounced(_ text: String, completion: @escaping @MainActor (NSAttributedString) -> Void) {
        debounceTask?.cancel()

        let delay = debounceDelay
        let highlighterRef = highlighter

        debounceTask = Task { @MainActor [weak self] in
            guard self != nil else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }

            let result = highlighterRef.highlight(text)
            completion(result)
        }
    }
}

// MARK: - Font Extension

extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits(rawValue: UInt32(traits.rawValue)))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }

    func withSize(_ size: CGFloat) -> NSFont {
        NSFont(descriptor: fontDescriptor, size: size) ?? self
    }

    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    /// Creates an NSColor from a hex string (e.g., "#FF5733" or "FF5733")
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB (ignore alpha for now)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1.0
        )
    }
}
