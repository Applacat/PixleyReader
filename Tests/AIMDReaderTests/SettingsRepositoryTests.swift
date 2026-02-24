import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// Since UserDefaultsSettingsRepository is in the main app (executable target),
// we mirror a simplified version here for testing persistence logic.
//
// IMPORTANT: These mirrors must match production types in:
//   Sources/Settings/SettingsRepository.swift
// Production uses decomposed containers (AppearanceSettings, RenderingSettings,
// BehaviorSettings) with typed enums. This test mirror uses a flat structure
// that exercises the same UserDefaults round-trip logic.

// MARK: - Setting Type Enums (mirror production)

/// Mirrors production SyntaxThemeSetting enum.
/// Production source: Sources/Settings/SettingsRepository.swift
private enum TestableSyntaxThemeSetting: String, CaseIterable {
    case xcode = "Xcode"
    case github = "GitHub"
    case solarized = "Solarized"
    case oneDark = "One Dark"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case nord = "Nord"

    /// Migration from legacy per-variant raw values, mirrors production init(migrating:)
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

/// Mirrors production HeadingScaleSetting enum
private enum TestableHeadingScaleSetting: String, CaseIterable {
    case compact
    case normal
    case spacious
}

/// Mirrors production LinkBehavior enum
private enum TestableLinkBehavior: String, CaseIterable {
    case browser
    case inApp
}

// MARK: - TestableSettingsRepository

@MainActor
private final class TestableSettingsRepository {
    let defaults: UserDefaults

    var fontSize: CGFloat {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }
    var fontFamily: String? {
        didSet {
            if let family = fontFamily {
                defaults.set(family, forKey: "fontFamily")
            } else {
                defaults.removeObject(forKey: "fontFamily")
            }
        }
    }
    var syntaxTheme: TestableSyntaxThemeSetting {
        didSet { defaults.set(syntaxTheme.rawValue, forKey: "syntaxTheme") }
    }
    var headingScale: TestableHeadingScaleSetting {
        didSet { defaults.set(headingScale.rawValue, forKey: "headingScale") }
    }
    var colorScheme: String? {
        didSet {
            if let scheme = colorScheme {
                defaults.set(scheme, forKey: "colorScheme")
            } else {
                defaults.removeObject(forKey: "colorScheme")
            }
        }
    }
    var linkBehavior: TestableLinkBehavior {
        didSet { defaults.set(linkBehavior.rawValue, forKey: "linkBehavior") }
    }
    var underlineLinks: Bool {
        didSet { defaults.set(underlineLinks, forKey: "underlineLinks") }
    }
    var showLineNumbers: Bool {
        didSet { defaults.set(showLineNumbers, forKey: "showLineNumbers") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults

        // Load persisted values with defaults
        self.fontSize = defaults.object(forKey: "fontSize") as? CGFloat ?? 14.0
        self.fontFamily = defaults.string(forKey: "fontFamily")

        // Theme: try direct rawValue init first, then migration for legacy values
        let themeRaw = defaults.string(forKey: "syntaxTheme") ?? TestableSyntaxThemeSetting.xcode.rawValue
        self.syntaxTheme = TestableSyntaxThemeSetting(rawValue: themeRaw)
            ?? TestableSyntaxThemeSetting(migrating: themeRaw)

        let scaleRaw = defaults.string(forKey: "headingScale") ?? TestableHeadingScaleSetting.normal.rawValue
        self.headingScale = TestableHeadingScaleSetting(rawValue: scaleRaw) ?? .normal

        self.colorScheme = defaults.string(forKey: "colorScheme")

        let linkRaw = defaults.string(forKey: "linkBehavior") ?? TestableLinkBehavior.browser.rawValue
        self.linkBehavior = TestableLinkBehavior(rawValue: linkRaw) ?? .browser

        if defaults.object(forKey: "underlineLinks") == nil {
            self.underlineLinks = true
        } else {
            self.underlineLinks = defaults.bool(forKey: "underlineLinks")
        }

        self.showLineNumbers = defaults.bool(forKey: "showLineNumbers")
    }
}

// MARK: - Tests

final class SettingsRepositoryTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.aimd.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
    }

    // MARK: - Load from UserDefaults

    @MainActor
    func testLoad_presetValues() {
        defaults.set(CGFloat(18.0), forKey: "fontSize")
        defaults.set("SF Mono", forKey: "fontFamily")
        defaults.set("Dracula", forKey: "syntaxTheme")
        defaults.set("spacious", forKey: "headingScale")
        defaults.set("dark", forKey: "colorScheme")
        defaults.set("inApp", forKey: "linkBehavior")
        defaults.set(false, forKey: "underlineLinks")
        defaults.set(true, forKey: "showLineNumbers")

        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.fontSize, 18.0)
        XCTAssertEqual(repo.fontFamily, "SF Mono")
        XCTAssertEqual(repo.syntaxTheme, .dracula)
        XCTAssertEqual(repo.headingScale, .spacious)
        XCTAssertEqual(repo.colorScheme, "dark")
        XCTAssertEqual(repo.linkBehavior, .inApp)
        XCTAssertFalse(repo.underlineLinks)
        XCTAssertTrue(repo.showLineNumbers)
    }

    // MARK: - Persist on Change

    @MainActor
    func testPersist_fontSizeWritesToDefaults() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.fontSize = 20.0
        XCTAssertEqual(defaults.double(forKey: "fontSize"), 20.0)
    }

    @MainActor
    func testPersist_fontFamilyWritesToDefaults() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.fontFamily = "New York"
        XCTAssertEqual(defaults.string(forKey: "fontFamily"), "New York")
    }

    @MainActor
    func testPersist_fontFamilyNil_removesKey() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.fontFamily = "SF Pro"
        XCTAssertNotNil(defaults.string(forKey: "fontFamily"))
        repo.fontFamily = nil
        XCTAssertNil(defaults.string(forKey: "fontFamily"))
    }

    @MainActor
    func testPersist_syntaxThemeWritesRawValueToDefaults() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.syntaxTheme = .dracula
        XCTAssertEqual(defaults.string(forKey: "syntaxTheme"), "Dracula")
    }

    @MainActor
    func testPersist_headingScaleWritesRawValueToDefaults() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.headingScale = .spacious
        XCTAssertEqual(defaults.string(forKey: "headingScale"), "spacious")
    }

    @MainActor
    func testPersist_linkBehaviorWritesRawValueToDefaults() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.linkBehavior = .inApp
        XCTAssertEqual(defaults.string(forKey: "linkBehavior"), "inApp")
    }

    // MARK: - Color Scheme Round-Trip

    @MainActor
    func testColorScheme_setDark_readsDark() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.colorScheme = "dark"
        XCTAssertEqual(defaults.string(forKey: "colorScheme"), "dark")
    }

    @MainActor
    func testColorScheme_setLight_readsLight() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.colorScheme = "light"
        XCTAssertEqual(defaults.string(forKey: "colorScheme"), "light")
    }

    @MainActor
    func testColorScheme_setNil_removesKey() {
        let repo = TestableSettingsRepository(defaults: defaults)
        repo.colorScheme = "dark"
        XCTAssertNotNil(defaults.string(forKey: "colorScheme"))
        repo.colorScheme = nil
        XCTAssertNil(defaults.string(forKey: "colorScheme"))
    }

    // MARK: - Theme Migration

    @MainActor
    func testThemeMigration_legacyXcodeDark_loadsAsXcode() {
        defaults.set("Xcode Dark", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .xcode)
    }

    @MainActor
    func testThemeMigration_legacyXcodeLight_loadsAsXcode() {
        defaults.set("Xcode Light", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .xcode)
    }

    @MainActor
    func testThemeMigration_legacyGitHubLight_loadsAsGitHub() {
        defaults.set("GitHub Light", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .github)
    }

    @MainActor
    func testThemeMigration_legacyGitHubDark_loadsAsGitHub() {
        defaults.set("GitHub Dark", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .github)
    }

    @MainActor
    func testThemeMigration_currentRawValue_passesThrough() {
        defaults.set("Dracula", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .dracula)
    }

    @MainActor
    func testThemeMigration_legacySolarizedLight_loadsAsSolarized() {
        defaults.set("Solarized Light", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .solarized)
    }

    @MainActor
    func testThemeMigration_legacySolarizedDark_loadsAsSolarized() {
        defaults.set("Solarized Dark", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .solarized)
    }

    @MainActor
    func testThemeMigration_unknownValue_fallsBackToXcode() {
        defaults.set("NonExistentTheme", forKey: "syntaxTheme")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertEqual(repo.syntaxTheme, .xcode)
    }

    // MARK: - underlineLinks nil → defaults to true

    @MainActor
    func testUnderlineLinks_nilDefaultsToTrue() {
        // Don't set the key at all
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertTrue(repo.underlineLinks)
    }

    @MainActor
    func testUnderlineLinks_explicitFalse_readsFalse() {
        defaults.set(false, forKey: "underlineLinks")
        let repo = TestableSettingsRepository(defaults: defaults)
        XCTAssertFalse(repo.underlineLinks)
    }
}
