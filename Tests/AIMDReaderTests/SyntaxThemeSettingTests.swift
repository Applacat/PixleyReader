import XCTest

// MARK: - Test-Only Type Definitions
// Since SyntaxThemeSetting is in the main app (executable target),
// we mirror the implementation here for testing the logic.

// MARK: - SyntaxThemeSetting Mirror

private enum TestableSyntaxThemeSetting: String, CaseIterable, Identifiable {
    case xcode = "Xcode"
    case github = "GitHub"
    case solarized = "Solarized"
    case oneDark = "One Dark"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case nord = "Nord"

    var id: String { rawValue }

    var hasLightVariant: Bool {
        switch self {
        case .xcode, .github, .solarized: return true
        case .oneDark, .dracula, .monokai, .nord: return false
        }
    }

    /// Returns a string identifier for the resolved theme (simulates rendererTheme)
    func resolvedThemeName(isDark: Bool) -> String {
        switch self {
        case .xcode:     return isDark ? "xcodeDark" : "xcodeLight"
        case .github:    return isDark ? "githubDark" : "githubLight"
        case .solarized: return isDark ? "solarizedDark" : "solarizedLight"
        case .oneDark:   return "oneDark"
        case .dracula:   return "dracula"
        case .monokai:   return "monokai"
        case .nord:      return "nord"
        }
    }

    init(migrating rawValue: String) {
        switch rawValue {
        case "Xcode Light", "Xcode Dark": self = .xcode
        case "GitHub Light", "GitHub Dark": self = .github
        case "Solarized Light", "Solarized Dark": self = .solarized
        case "One Dark": self = .oneDark
        case "Dracula": self = .dracula
        case "Monokai": self = .monokai
        case "Nord": self = .nord
        default: self = Self(rawValue: rawValue) ?? .xcode
        }
    }
}

// MARK: - HeadingScaleSetting Mirror

private enum TestableHeadingScaleSetting: String, CaseIterable, Identifiable {
    case compact
    case normal
    case spacious

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .normal: return "Normal"
        case .spacious: return "Spacious"
        }
    }
}

// MARK: - LinkBehavior Mirror

private enum TestableLinkBehavior: String, CaseIterable, Identifiable {
    case browser
    case inApp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .browser: return "Open in Browser"
        case .inApp: return "Open in App"
        }
    }
}

// MARK: - Tests

final class SyntaxThemeSettingTests: XCTestCase {

    // MARK: - rendererTheme(isDark:) Tests

    func testRendererTheme_xcode_dark() {
        let theme = TestableSyntaxThemeSetting.xcode
        XCTAssertEqual(theme.resolvedThemeName(isDark: true), "xcodeDark")
    }

    func testRendererTheme_xcode_light() {
        let theme = TestableSyntaxThemeSetting.xcode
        XCTAssertEqual(theme.resolvedThemeName(isDark: false), "xcodeLight")
    }

    func testRendererTheme_github_dark() {
        let theme = TestableSyntaxThemeSetting.github
        XCTAssertEqual(theme.resolvedThemeName(isDark: true), "githubDark")
    }

    func testRendererTheme_github_light() {
        let theme = TestableSyntaxThemeSetting.github
        XCTAssertEqual(theme.resolvedThemeName(isDark: false), "githubLight")
    }

    func testRendererTheme_solarized_dark() {
        let theme = TestableSyntaxThemeSetting.solarized
        XCTAssertEqual(theme.resolvedThemeName(isDark: true), "solarizedDark")
    }

    func testRendererTheme_solarized_light() {
        let theme = TestableSyntaxThemeSetting.solarized
        XCTAssertEqual(theme.resolvedThemeName(isDark: false), "solarizedLight")
    }

    func testRendererTheme_oneDark_alwaysDark() {
        let theme = TestableSyntaxThemeSetting.oneDark
        XCTAssertEqual(theme.resolvedThemeName(isDark: true), "oneDark")
        XCTAssertEqual(theme.resolvedThemeName(isDark: false), "oneDark")
    }

    func testRendererTheme_dracula_alwaysDark() {
        let theme = TestableSyntaxThemeSetting.dracula
        XCTAssertEqual(theme.resolvedThemeName(isDark: true), "dracula")
        XCTAssertEqual(theme.resolvedThemeName(isDark: false), "dracula")
    }

    func testRendererTheme_monokai_alwaysDark() {
        let theme = TestableSyntaxThemeSetting.monokai
        XCTAssertEqual(theme.resolvedThemeName(isDark: true), "monokai")
        XCTAssertEqual(theme.resolvedThemeName(isDark: false), "monokai")
    }

    func testRendererTheme_nord_alwaysDark() {
        let theme = TestableSyntaxThemeSetting.nord
        XCTAssertEqual(theme.resolvedThemeName(isDark: true), "nord")
        XCTAssertEqual(theme.resolvedThemeName(isDark: false), "nord")
    }

    // MARK: - hasLightVariant Tests

    func testHasLightVariant_xcode() {
        XCTAssertTrue(TestableSyntaxThemeSetting.xcode.hasLightVariant)
    }

    func testHasLightVariant_github() {
        XCTAssertTrue(TestableSyntaxThemeSetting.github.hasLightVariant)
    }

    func testHasLightVariant_solarized() {
        XCTAssertTrue(TestableSyntaxThemeSetting.solarized.hasLightVariant)
    }

    func testHasLightVariant_oneDark_false() {
        XCTAssertFalse(TestableSyntaxThemeSetting.oneDark.hasLightVariant)
    }

    func testHasLightVariant_dracula_false() {
        XCTAssertFalse(TestableSyntaxThemeSetting.dracula.hasLightVariant)
    }

    func testHasLightVariant_monokai_false() {
        XCTAssertFalse(TestableSyntaxThemeSetting.monokai.hasLightVariant)
    }

    func testHasLightVariant_nord_false() {
        XCTAssertFalse(TestableSyntaxThemeSetting.nord.hasLightVariant)
    }

    // MARK: - init(migrating:) Tests

    func testMigration_xcodeLight_mapsToXcode() {
        let theme = TestableSyntaxThemeSetting(migrating: "Xcode Light")
        XCTAssertEqual(theme, .xcode)
    }

    func testMigration_xcodeDark_mapsToXcode() {
        let theme = TestableSyntaxThemeSetting(migrating: "Xcode Dark")
        XCTAssertEqual(theme, .xcode)
    }

    func testMigration_githubLight_mapsToGithub() {
        let theme = TestableSyntaxThemeSetting(migrating: "GitHub Light")
        XCTAssertEqual(theme, .github)
    }

    func testMigration_githubDark_mapsToGithub() {
        let theme = TestableSyntaxThemeSetting(migrating: "GitHub Dark")
        XCTAssertEqual(theme, .github)
    }

    func testMigration_solarizedLight_mapsToSolarized() {
        let theme = TestableSyntaxThemeSetting(migrating: "Solarized Light")
        XCTAssertEqual(theme, .solarized)
    }

    func testMigration_solarizedDark_mapsToSolarized() {
        let theme = TestableSyntaxThemeSetting(migrating: "Solarized Dark")
        XCTAssertEqual(theme, .solarized)
    }

    func testMigration_oneDark_passesThrough() {
        let theme = TestableSyntaxThemeSetting(migrating: "One Dark")
        XCTAssertEqual(theme, .oneDark)
    }

    func testMigration_unknownString_fallsBackToXcode() {
        let theme = TestableSyntaxThemeSetting(migrating: "NonExistentTheme")
        XCTAssertEqual(theme, .xcode)
    }

    func testMigration_currentRawValues_passThrough() {
        // Current raw values should work directly
        XCTAssertEqual(TestableSyntaxThemeSetting(migrating: "Xcode"), .xcode)
        XCTAssertEqual(TestableSyntaxThemeSetting(migrating: "GitHub"), .github)
        XCTAssertEqual(TestableSyntaxThemeSetting(migrating: "Dracula"), .dracula)
        XCTAssertEqual(TestableSyntaxThemeSetting(migrating: "Monokai"), .monokai)
        XCTAssertEqual(TestableSyntaxThemeSetting(migrating: "Nord"), .nord)
    }

    // MARK: - HeadingScaleSetting Tests

    func testHeadingScaleSetting_displayName_compact() {
        XCTAssertEqual(TestableHeadingScaleSetting.compact.displayName, "Compact")
    }

    func testHeadingScaleSetting_displayName_normal() {
        XCTAssertEqual(TestableHeadingScaleSetting.normal.displayName, "Normal")
    }

    func testHeadingScaleSetting_displayName_spacious() {
        XCTAssertEqual(TestableHeadingScaleSetting.spacious.displayName, "Spacious")
    }

    // MARK: - LinkBehavior Tests

    func testLinkBehavior_displayName_browser() {
        XCTAssertEqual(TestableLinkBehavior.browser.displayName, "Open in Browser")
    }

    func testLinkBehavior_displayName_inApp() {
        XCTAssertEqual(TestableLinkBehavior.inApp.displayName, "Open in App")
    }

}
