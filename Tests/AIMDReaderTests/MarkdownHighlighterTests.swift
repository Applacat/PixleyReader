import XCTest
import AppKit

// MARK: - Test-Only Type Definitions
// Since MarkdownHighlighter is in the main app (executable target),
// we mirror the implementation here for testing the logic.

// MARK: - MarkdownConfig Mirror

private enum TestableMarkdownConfig {
    static let maxTextSize = 10_485_760       // 10MB
    static let maxHighlightSize = 1_048_576   // 1MB
}

// MARK: - HeadingScale Mirror

private enum TestableHeadingScale {
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

// MARK: - NSColor(hex:) Mirror

private extension NSColor {
    convenience init?(testHex hex: String) {
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

// MARK: - Highlight Rule Mirror

private enum TestableHighlightRule {
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

// MARK: - NSFont Extensions Mirror

private extension NSFont {
    func testWithTraits(_ traits: NSFontTraitMask) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits(rawValue: UInt32(traits.rawValue)))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }

    func testWithSize(_ size: CGFloat) -> NSFont {
        NSFont(descriptor: fontDescriptor, size: size) ?? self
    }

    func testWithWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

// MARK: - resolveFont Mirror

private func testResolveFont(family: String?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
    guard let family else {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    switch family {
    case "New York":
        let descriptor = NSFont.systemFont(ofSize: size, weight: weight)
            .fontDescriptor.withDesign(.serif)
        return descriptor.flatMap { NSFont(descriptor: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    case "SF Pro":
        return NSFont.systemFont(ofSize: size, weight: weight)
    case "SF Mono":
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    default:
        return NSFont(name: family, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - TestableHighlighter

private struct TestableHighlighterTheme {
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

    /// Creates a theme from hex palette values, mirroring production
    /// Theme(from: SyntaxPalette) initializer.
    ///
    /// Production source: MarkdownHighlighter.swift Theme.init(from:)
    /// Palette source: SyntaxTheme.xcodeDark.palette
    static let `default`: TestableHighlighterTheme = {
        // Xcode Dark palette hex values from aimdRenderer
        let palette = (
            type: "#ACF2E4",      // heading1
            function: "#67B7A4",  // heading2, link
            keyword: "#FF7AB2",   // heading3
            foreground: "#FFFFFF", // bold, italic, foreground
            string: "#FF8170",    // code
            selection: "#515B70", // codeBackground (with 0.3 alpha)
            comment: "#7F8C98",   // listMarker, blockquote
            lineNumber: "#6C6C6C", // separator
            background: "#1F1F24"  // background
        )

        return TestableHighlighterTheme(
            heading1: NSColor(testHex: palette.type) ?? .systemBlue,
            heading2: NSColor(testHex: palette.function) ?? .systemIndigo,
            heading3: NSColor(testHex: palette.keyword) ?? .systemPurple,
            bold: NSColor(testHex: palette.foreground) ?? .labelColor,
            italic: NSColor(testHex: palette.foreground) ?? .labelColor,
            code: NSColor(testHex: palette.string) ?? .systemOrange,
            codeBackground: (NSColor(testHex: palette.selection) ?? .quaternaryLabelColor).withAlphaComponent(0.3),
            link: NSColor(testHex: palette.function) ?? .systemTeal,
            listMarker: NSColor(testHex: palette.comment) ?? .systemGray,
            blockquote: NSColor(testHex: palette.comment) ?? .secondaryLabelColor,
            separator: NSColor(testHex: palette.lineNumber) ?? .separatorColor,
            foreground: NSColor(testHex: palette.foreground) ?? .labelColor,
            background: NSColor(testHex: palette.background) ?? .textBackgroundColor
        )
    }()
}

private final class TestableHighlighter {
    let theme: TestableHighlighterTheme
    let baseFont: NSFont
    let headingScale: TestableHeadingScale
    let patterns: [(NSRegularExpression, TestableHighlightRule)]

    init(theme: TestableHighlighterTheme = .default, fontSize: CGFloat = 14, fontFamily: String? = nil, headingScale: TestableHeadingScale = .normal) {
        self.theme = theme
        self.headingScale = headingScale
        self.baseFont = testResolveFont(family: fontFamily, size: fontSize, weight: .regular)
        self.patterns = Self.compilePatterns()
    }

    private static func compilePatterns() -> [(NSRegularExpression, TestableHighlightRule)] {
        let definitions: [(String, TestableHighlightRule)] = [
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

    func highlight(_ text: String) -> NSAttributedString {
        guard text.utf8.count <= TestableMarkdownConfig.maxHighlightSize else {
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

    private func applyRule(_ rule: TestableHighlightRule, to str: NSMutableAttributedString, match: NSTextCheckingResult) {
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
            let headingFont = baseFont.testWithSize(size).testWithWeight(.bold)
            str.addAttributes([
                .foregroundColor: color,
                .font: headingFont
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
            str.addAttribute(.font, value: baseFont.testWithWeight(.bold), range: match.range)

        case .italic:
            let italicFont = baseFont.testWithTraits(.italicFontMask)
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
}

// MARK: - Tests

final class MarkdownHighlighterTests: XCTestCase {

    // MARK: - NSColor(hex:) Tests

    func testNSColorHex_6CharRGB() {
        let color = NSColor(testHex: "FF5733")
        XCTAssertNotNil(color)
        // Check the red component is correct (FF = 255 → 1.0)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 87.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 51.0 / 255.0, accuracy: 0.01)
    }

    func testNSColorHex_6CharWithHash() {
        let color = NSColor(testHex: "#00FF00")
        XCTAssertNotNil(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 1.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testNSColorHex_8CharARGB() {
        // "FF00FF00" — 8-char ARGB format. The implementation ignores the alpha byte
        // and parses bytes 3-8 as: R=00, G=FF, B=00 (same as 6-char parse of "00FF00")
        let color = NSColor(testHex: "FF00FF00")
        XCTAssertNotNil(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        // 8-char path: int >> 16 = 0x00FF, & 0xFF = 0xFF => but wait:
        // For "FF00FF00": int = 0xFF00FF00
        // r = (int >> 16) & 0xFF = (0xFF00) & 0xFF = 0x00 = 0
        // g = (int >> 8) & 0xFF  = (0xFF00FF) & 0xFF = 0xFF = 255
        // b = int & 0xFF         = 0xFF00FF00 & 0xFF = 0x00 = 0
        XCTAssertEqual(r, 0.0, accuracy: 0.01, "Red component should be 0")
        XCTAssertEqual(g, 1.0, accuracy: 0.01, "Green component should be 1.0 (0xFF)")
        XCTAssertEqual(b, 0.0, accuracy: 0.01, "Blue component should be 0")
    }

    func testNSColorHex_invalidInput_returnsNil() {
        XCTAssertNil(NSColor(testHex: "XYZ"))
        XCTAssertNil(NSColor(testHex: "12345"))  // 5 chars - not 6 or 8
        XCTAssertNil(NSColor(testHex: "1"))
    }

    func testNSColorHex_emptyString_returnsNil() {
        XCTAssertNil(NSColor(testHex: ""))
    }

    // MARK: - HeadingScale Tests

    func testHeadingScale_compactMultipliers() {
        let scale = TestableHeadingScale.compact
        let m = scale.multipliers
        XCTAssertEqual(m.h1, 1.1, accuracy: 0.001)
        XCTAssertEqual(m.h2, 1.05, accuracy: 0.001)
        XCTAssertEqual(m.h3, 1.0, accuracy: 0.001)
    }

    func testHeadingScale_normalMultipliers() {
        let scale = TestableHeadingScale.normal
        let m = scale.multipliers
        XCTAssertEqual(m.h1, 1.6, accuracy: 0.001)
        XCTAssertEqual(m.h2, 1.4, accuracy: 0.001)
        XCTAssertEqual(m.h3, 1.2, accuracy: 0.001)
    }

    func testHeadingScale_spaciousMultipliers() {
        let scale = TestableHeadingScale.spacious
        let m = scale.multipliers
        XCTAssertEqual(m.h1, 2.0, accuracy: 0.001)
        XCTAssertEqual(m.h2, 1.7, accuracy: 0.001)
        XCTAssertEqual(m.h3, 1.4, accuracy: 0.001)
    }

    // MARK: - MarkdownConfig Tests

    func testMarkdownConfig_maxTextSize() {
        XCTAssertEqual(TestableMarkdownConfig.maxTextSize, 10_485_760)
    }

    func testMarkdownConfig_maxHighlightSize() {
        XCTAssertEqual(TestableMarkdownConfig.maxHighlightSize, 1_048_576)
    }

    // MARK: - highlight() Heading Tests

    func testHighlight_h1_getsCorrectFontSize() {
        let highlighter = TestableHighlighter(fontSize: 14, headingScale: .normal)
        let result = highlighter.highlight("# Heading 1")

        // H1 with normal scale: 14 * 1.6 = 22.4
        var range = NSRange()
        let font = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertEqual(font?.pointSize ?? 0, 22.4, accuracy: 0.1)
    }

    func testHighlight_h2_getsCorrectFontSize() {
        let highlighter = TestableHighlighter(fontSize: 14, headingScale: .normal)
        let result = highlighter.highlight("## Heading 2")

        var range = NSRange()
        let font = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        XCTAssertNotNil(font)
        // H2 with normal scale: 14 * 1.4 = 19.6
        XCTAssertEqual(font?.pointSize ?? 0, 19.6, accuracy: 0.1)
    }

    func testHighlight_h3_getsCorrectFontSize() {
        let highlighter = TestableHighlighter(fontSize: 14, headingScale: .normal)
        let result = highlighter.highlight("### Heading 3")

        var range = NSRange()
        let font = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        XCTAssertNotNil(font)
        // H3 with normal scale: 14 * 1.2 = 16.8
        XCTAssertEqual(font?.pointSize ?? 0, 16.8, accuracy: 0.1)
    }

    func testHighlight_h1_getsHeading1Color() {
        let highlighter = TestableHighlighter(fontSize: 14)
        let result = highlighter.highlight("# Heading 1")

        var range = NSRange()
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
        XCTAssertNotNil(color, "Heading 1 should have a foreground color")
        // Heading color must differ from the base foreground, proving highlighting occurred.
        // We don't assert a specific system color because production derives from palette hex values.
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Heading 1 color should differ from base foreground")
    }

    func testHighlight_h2_getsHeading2Color() {
        let highlighter = TestableHighlighter(fontSize: 14)
        let result = highlighter.highlight("## Heading 2")

        var range = NSRange()
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
        XCTAssertNotNil(color, "Heading 2 should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Heading 2 color should differ from base foreground")
    }

    func testHighlight_h3_getsHeading3Color() {
        let highlighter = TestableHighlighter(fontSize: 14)
        let result = highlighter.highlight("### Heading 3")

        var range = NSRange()
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
        XCTAssertNotNil(color, "Heading 3 should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Heading 3 color should differ from base foreground")
    }

    func testHighlight_h1_withCompactScale() {
        let highlighter = TestableHighlighter(fontSize: 14, headingScale: .compact)
        let result = highlighter.highlight("# Heading 1")

        var range = NSRange()
        let font = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        // H1 with compact scale: 14 * 1.1 = 15.4
        XCTAssertEqual(font?.pointSize ?? 0, 15.4, accuracy: 0.1)
    }

    func testHighlight_h1_withSpaciousScale() {
        let highlighter = TestableHighlighter(fontSize: 14, headingScale: .spacious)
        let result = highlighter.highlight("# Heading 1")

        var range = NSRange()
        let font = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        // H1 with spacious scale: 14 * 2.0 = 28.0
        XCTAssertEqual(font?.pointSize ?? 0, 28.0, accuracy: 0.1)
    }

    // MARK: - highlight() Code Tests

    func testHighlight_inlineCode_getsCodeColor() {
        let highlighter = TestableHighlighter()
        let text = "Some `inline code` here"
        let result = highlighter.highlight(text)

        // Find the backtick position
        let codeStart = (text as NSString).range(of: "`inline code`").location
        var range = NSRange()
        let color = result.attribute(.foregroundColor, at: codeStart, effectiveRange: &range) as? NSColor
        XCTAssertNotNil(color, "Inline code should have a foreground color")
        // Code color should differ from base foreground, proving the code rule was applied.
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Inline code color should differ from base foreground")
    }

    func testHighlight_inlineCode_getsCodeBackground() {
        let highlighter = TestableHighlighter()
        let text = "Some `inline code` here"
        let result = highlighter.highlight(text)

        let codeStart = (text as NSString).range(of: "`inline code`").location
        let bg = result.attribute(.backgroundColor, at: codeStart, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(bg, "Inline code should have a background color attribute")
        // The background must differ from the foreground, proving a distinct code background was set
        let fg = result.attribute(.foregroundColor, at: codeStart, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(bg, fg,
            "Code background color should be distinct from the foreground color")
    }

    func testHighlight_codeBlock_getsMonospacedFont() {
        let highlighter = TestableHighlighter(fontSize: 14, fontFamily: "SF Pro")
        let text = "```\nlet x = 1\n```"
        let result = highlighter.highlight(text)

        var range = NSRange()
        let font = result.attribute(.font, at: 4, effectiveRange: &range) as? NSFont
        XCTAssertNotNil(font)
        // Code blocks should use monospaced font even when base is SF Pro
        let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        XCTAssertEqual(font?.fontName, monoFont.fontName)
    }

    // MARK: - highlight() Bold/Italic Tests

    func testHighlight_bold_getsBoldWeight() {
        // Use SF Pro since monospaced system fonts may not resolve bold via descriptors
        let highlighter = TestableHighlighter(fontSize: 14, fontFamily: "SF Pro")
        let text = "Some **bold text** here"
        let result = highlighter.highlight(text)

        let boldStart = (text as NSString).range(of: "**bold text**").location
        let font = result.attribute(.font, at: boldStart, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        // Bold font should differ from the base font (which is regular weight)
        let baseFont = highlighter.baseFont
        XCTAssertNotEqual(font, baseFont, "Bold text should have a different font than the base")
    }

    func testHighlight_italic_getsItalicTrait() {
        let highlighter = TestableHighlighter(fontSize: 14)
        let text = "Some *italic text* here"
        let result = highlighter.highlight(text)

        let italicStart = (text as NSString).range(of: "*italic text*").location
        let font = result.attribute(.font, at: italicStart, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        let traits = NSFontManager.shared.traits(of: font!)
        XCTAssertTrue(traits.contains(.italicFontMask))
    }

    // MARK: - highlight() Link Tests

    func testHighlight_link_getsLinkColor() {
        let highlighter = TestableHighlighter()
        let text = "Click [here](https://example.com) now"
        let result = highlighter.highlight(text)

        let linkStart = (text as NSString).range(of: "[here](https://example.com)").location
        let color = result.attribute(.foregroundColor, at: linkStart, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Link should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Link color should differ from base foreground")
    }

    // MARK: - highlight() List Marker Tests

    func testHighlight_dashListMarker_getsListMarkerColor() {
        let highlighter = TestableHighlighter()
        let result = highlighter.highlight("- item")

        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Dash list marker should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "List marker color should differ from base foreground")
    }

    func testHighlight_asteriskListMarker_getsListMarkerColor() {
        let highlighter = TestableHighlighter()
        let result = highlighter.highlight("* item")

        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Asterisk list marker should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "List marker color should differ from base foreground")
    }

    func testHighlight_numberedListMarker_getsListMarkerColor() {
        let highlighter = TestableHighlighter()
        let result = highlighter.highlight("1. item")

        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Numbered list marker should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "List marker color should differ from base foreground")
    }

    // MARK: - highlight() Blockquote Tests

    func testHighlight_blockquote_getsBlockquoteColor() {
        let highlighter = TestableHighlighter()
        let result = highlighter.highlight("> This is a quote")

        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Blockquote should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Blockquote color should differ from base foreground")
    }

    // MARK: - highlight() Separator Tests

    func testHighlight_dashSeparator_getsSeparatorColor() {
        let highlighter = TestableHighlighter()
        let result = highlighter.highlight("---")

        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Dash separator should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Separator color should differ from base foreground")
    }

    func testHighlight_asteriskSeparator_getsSeparatorColor() {
        let highlighter = TestableHighlighter()
        let result = highlighter.highlight("***")

        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Asterisk separator should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Separator color should differ from base foreground")
    }

    func testHighlight_underscoreSeparator_getsSeparatorColor() {
        let highlighter = TestableHighlighter()
        let result = highlighter.highlight("___")

        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Underscore separator should have a foreground color")
        XCTAssertNotEqual(color, highlighter.theme.foreground,
            "Separator color should differ from base foreground")
    }

    // MARK: - highlight() Edge Case Tests

    func testHighlight_oversizedText_returnsPlainText() {
        let highlighter = TestableHighlighter(fontSize: 14)
        // Create a string larger than 1MB
        let oversized = String(repeating: "# Heading\n", count: 200_000)
        XCTAssertGreaterThan(oversized.utf8.count, TestableMarkdownConfig.maxHighlightSize)

        let result = highlighter.highlight(oversized)

        // Should have base font only (no heading scaling)
        var range = NSRange()
        let font = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testHighlight_emptyString_returnsEmptyAttributedString() {
        let highlighter = TestableHighlighter(fontSize: 14)
        let result = highlighter.highlight("")

        XCTAssertEqual(result.length, 0)
    }

    // MARK: - resolveFont Tests

    func testResolveFont_nilFamily_returnsMonospaced() {
        let font = testResolveFont(family: nil, size: 14, weight: .regular)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        XCTAssertEqual(font.fontName, monoFont.fontName)
    }

    func testResolveFont_SFPro_returnsSystemFont() {
        let font = testResolveFont(family: "SF Pro", size: 14, weight: .regular)
        let systemFont = NSFont.systemFont(ofSize: 14, weight: .regular)
        XCTAssertEqual(font.fontName, systemFont.fontName)
    }

    func testResolveFont_SFMono_returnsMonospaced() {
        let font = testResolveFont(family: "SF Mono", size: 14, weight: .regular)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        XCTAssertEqual(font.fontName, monoFont.fontName)
    }

    func testResolveFont_NewYork_returnsSerifDesign() {
        let font = testResolveFont(family: "New York", size: 14, weight: .regular)
        // New York should resolve to a serif design
        // Check it has a reasonable size
        XCTAssertEqual(font.pointSize, 14)
        // Verify it's not the monospaced fallback
        let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        XCTAssertNotEqual(font.fontName, monoFont.fontName)
    }

    func testResolveFont_unknownFamily_fallsBackToMonospaced() {
        let font = testResolveFont(family: "NonExistentFont12345", size: 14, weight: .regular)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        XCTAssertEqual(font.fontName, monoFont.fontName)
    }

    func testResolveFont_respectsSize() {
        let font = testResolveFont(family: nil, size: 20, weight: .regular)
        XCTAssertEqual(font.pointSize, 20)
    }
}
