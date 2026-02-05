import Testing
import Foundation
@testable import aimdRenderer

@Suite("Theme System Tests")
struct ThemeTests {

    // MARK: - Syntax Theme Tests

    @Test("All syntax themes have palettes")
    func allThemesHavePalettes() {
        for theme in SyntaxTheme.allCases {
            let palette = theme.palette
            #expect(!palette.background.isEmpty)
            #expect(!palette.foreground.isEmpty)
            #expect(!palette.keyword.isEmpty)
        }
    }

    @Test("Syntax themes have correct dark/light classification")
    func darkLightClassification() {
        // Light themes
        #expect(SyntaxTheme.xcodeLight.isDark == false)
        #expect(SyntaxTheme.githubLight.isDark == false)
        #expect(SyntaxTheme.solarizedLight.isDark == false)

        // Dark themes
        #expect(SyntaxTheme.xcodeDark.isDark == true)
        #expect(SyntaxTheme.githubDark.isDark == true)
        #expect(SyntaxTheme.oneDark.isDark == true)
        #expect(SyntaxTheme.dracula.isDark == true)
        #expect(SyntaxTheme.solarizedDark.isDark == true)
        #expect(SyntaxTheme.monokai.isDark == true)
        #expect(SyntaxTheme.nord.isDark == true)
    }

    @Test("All 10+ themes are available")
    func tenPlusThemes() {
        #expect(SyntaxTheme.allCases.count >= 10)
    }

    // MARK: - Theme Configuration Tests

    @Test("Default configuration has sensible values")
    func defaultConfiguration() {
        let config = ThemeConfiguration()
        #expect(config.fontSize == 14)
        #expect(config.fontFamily == nil)
        #expect(config.syntaxTheme == .xcodeDark)
        #expect(config.headingScale == .normal)
        #expect(config.showLineNumbers == false)
        #expect(config.underlineLinks == true)
    }

    @Test("Configuration can be customized")
    func customConfiguration() {
        let config = ThemeConfiguration(
            fontSize: 18,
            fontFamily: "Menlo",
            syntaxTheme: .dracula,
            headingScale: .spacious,
            showLineNumbers: true,
            underlineLinks: false
        )

        #expect(config.fontSize == 18)
        #expect(config.fontFamily == "Menlo")
        #expect(config.syntaxTheme == .dracula)
        #expect(config.headingScale == .spacious)
        #expect(config.showLineNumbers == true)
        #expect(config.underlineLinks == false)
    }

    // MARK: - Heading Scale Tests

    @Test("Heading scale factors decrease with level")
    func headingScaleFactors() {
        for scale in HeadingScale.allCases {
            let h1 = scale.factor(for: 1)
            let h2 = scale.factor(for: 2)
            let h3 = scale.factor(for: 3)
            let h4 = scale.factor(for: 4)
            let h5 = scale.factor(for: 5)
            let h6 = scale.factor(for: 6)

            // Each subsequent heading should be smaller or equal
            #expect(h1 >= h2)
            #expect(h2 >= h3)
            #expect(h3 >= h4)
            #expect(h4 >= h5)
            #expect(h5 >= h6)

            // All factors should be positive
            #expect(h1 > 0)
            #expect(h6 > 0)
        }
    }

    @Test("Spacious scale is larger than compact")
    func scaleOrdering() {
        let h1Compact = HeadingScale.compact.factor(for: 1)
        let h1Normal = HeadingScale.normal.factor(for: 1)
        let h1Spacious = HeadingScale.spacious.factor(for: 1)

        #expect(h1Spacious > h1Normal)
        #expect(h1Normal > h1Compact)
    }

    // MARK: - Palette Color Tests

    @Test("Xcode Dark palette has valid hex colors")
    func xcodeDarkPaletteColors() {
        let palette = SyntaxPalette.xcodeDark
        #expect(isValidHex(palette.background))
        #expect(isValidHex(palette.foreground))
        #expect(isValidHex(palette.keyword))
        #expect(isValidHex(palette.string))
        #expect(isValidHex(palette.comment))
        #expect(isValidHex(palette.number))
        #expect(isValidHex(palette.type))
        #expect(isValidHex(palette.function))
        #expect(isValidHex(palette.property))
        #expect(isValidHex(palette.operator))
        #expect(isValidHex(palette.preprocessor))
    }

    // MARK: - Helper

    private func isValidHex(_ hex: String) -> Bool {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6 || trimmed.count == 8 else { return false }
        return trimmed.allSatisfy { $0.isHexDigit }
    }
}

// MARK: - SwiftUI Theme Tests

@Suite("SwiftUI Theme Tests")
@MainActor
struct SwiftUIThemeTests {

    @Test("SwiftUI theme can render heading")
    func renderHeading() async {
        let theme = SwiftUITheme()
        let heading = HeadingInfo(level: 1, text: "Test Heading")
        let view = theme.render(heading: heading)
        #expect(view != nil)
    }

    @Test("SwiftUI theme can render paragraph")
    func renderParagraph() async {
        let theme = SwiftUITheme()
        let paragraph = ParagraphInfo(text: "Test paragraph content.")
        let view = theme.render(paragraph: paragraph)
        #expect(view != nil)
    }

    @Test("SwiftUI theme can render code block")
    func renderCodeBlock() async {
        let theme = SwiftUITheme()
        let codeBlock = CodeBlockInfo(
            language: "swift",
            code: "let x = 42"
        )
        let view = theme.render(codeBlock: codeBlock)
        #expect(view != nil)
    }

    @Test("SwiftUI theme can render document")
    func renderDocument() async {
        let theme = SwiftUITheme()
        let document = DocumentModel(content: "# Hello\n\nWorld")
        let view = theme.render(document: document)
        #expect(view != nil)
    }

    @Test("SwiftUI theme respects configuration")
    func respectsConfiguration() async {
        let config = ThemeConfiguration(
            fontSize: 20,
            syntaxTheme: .dracula
        )
        let theme = SwiftUITheme(configuration: config)
        #expect(theme.configuration.fontSize == 20)
        #expect(theme.configuration.syntaxTheme == .dracula)
    }
}
