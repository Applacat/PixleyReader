import AppKit
import Foundation

/// A focused Markdown highlighter with lazy-compiled patterns and debouncing support
@MainActor
final class MarkdownHighlighter {

    // MARK: - Theme

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

        static let `default` = Theme(
            heading1: .systemBlue,
            heading2: .systemIndigo,
            heading3: .systemPurple,
            bold: .labelColor,
            italic: .labelColor,
            code: .systemOrange,
            codeBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.3),
            link: .systemTeal,
            listMarker: .systemGray,
            blockquote: .secondaryLabelColor,
            separator: .separatorColor
        )
    }

    // MARK: - Properties

    let theme: Theme
    let baseFont: NSFont

    /// Compiled patterns - created once, reused for every highlight call
    private let patterns: [(NSRegularExpression, HighlightRule)]

    // MARK: - Debouncing

    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 0.1

    // MARK: - Highlight Rules

    private enum HighlightRule {
        case heading
        case codeBlock
        case inlineCode
        case bold
        case italic
        case link
        case listMarker
        case blockquote
        case separator
    }

    // MARK: - Initialization

    init(theme: Theme = .default, fontSize: CGFloat = 14) {
        self.theme = theme
        self.baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.patterns = Self.compilePatterns()
    }

    // MARK: - Pattern Compilation

    private static func compilePatterns() -> [(NSRegularExpression, HighlightRule)] {
        let definitions: [(String, HighlightRule)] = [
            (#"^(#{1,6})\s+(.+)$"#, .heading),
            (#"```[\s\S]*?```"#, .codeBlock),
            (#"`[^`\n]+`"#, .inlineCode),
            (#"\*\*(.+?)\*\*|__(.+?)__"#, .bold),
            (#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, .italic),
            (#"\[([^\]]+)\]\([^\)]+\)"#, .link),
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

    // MARK: - Highlighting

    func highlight(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
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
            let color: NSColor
            let size: CGFloat
            switch hashCount {
            case 1: color = theme.heading1; size = baseFont.pointSize * 1.6
            case 2: color = theme.heading2; size = baseFont.pointSize * 1.4
            default: color = theme.heading3; size = baseFont.pointSize * 1.2
            }
            str.addAttributes([
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: size, weight: .bold)
            ], range: match.range)

        case .codeBlock:
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
            str.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold), range: match.range)

        case .italic:
            let italicFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .regular).withTraits(.italicFontMask)
            str.addAttribute(.font, value: italicFont, range: match.range)

        case .link:
            str.addAttribute(.foregroundColor, value: theme.link, range: match.range)

        case .listMarker:
            str.addAttribute(.foregroundColor, value: theme.listMarker, range: match.range)

        case .blockquote:
            str.addAttribute(.foregroundColor, value: theme.blockquote, range: match.range)

        case .separator:
            str.addAttribute(.foregroundColor, value: theme.separator, range: match.range)
        }
    }

    /// Debounced highlighting - call this from text change handlers
    nonisolated func highlightDebounced(_ text: String, completion: @escaping @MainActor (NSAttributedString) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.debounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    let result = self.highlight(text)
                    completion(result)
                }
            }

            self.debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.debounceDelay,
                execute: workItem
            )
        }
    }
}

// MARK: - Font Extension

extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits(rawValue: UInt32(traits.rawValue)))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
