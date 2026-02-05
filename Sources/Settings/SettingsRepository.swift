import SwiftUI

// MARK: - Settings Repository Protocol

/// Protocol defining access to application settings.
///
/// OOD Pattern: Repository abstraction separates setting storage from usage.
/// Views access settings through this protocol, not directly through @AppStorage.
/// This enables:
/// 1. Testability - mock settings in tests
/// 2. Migration - change storage mechanism without updating views
/// 3. Centralized defaults - all defaults defined in one place
@MainActor
public protocol SettingsRepository {
    /// Appearance-related settings
    var appearance: AppearanceSettings { get set }

    /// Markdown rendering settings
    var rendering: RenderingSettings { get set }

    /// Behavior and interaction settings
    var behavior: BehaviorSettings { get set }
}

// MARK: - Settings Containers

/// Appearance settings (color scheme, theme)
@MainActor
@Observable
public final class AppearanceSettings {
    /// Color scheme preference (nil = follow system)
    /// Note: This is session-only, not persisted
    public var colorScheme: ColorScheme? = nil
}

/// Markdown rendering settings
@MainActor
@Observable
public final class RenderingSettings {
    /// Base font size in points
    public var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    /// Font family name (nil = system default)
    public var fontFamily: String? {
        didSet {
            if let family = fontFamily {
                UserDefaults.standard.set(family, forKey: "fontFamily")
            } else {
                UserDefaults.standard.removeObject(forKey: "fontFamily")
            }
        }
    }

    /// Syntax highlighting theme
    public var syntaxTheme: SyntaxThemeSetting {
        didSet { UserDefaults.standard.set(syntaxTheme.rawValue, forKey: "syntaxTheme") }
    }

    /// Heading size scale
    public var headingScale: HeadingScaleSetting {
        didSet { UserDefaults.standard.set(headingScale.rawValue, forKey: "headingScale") }
    }

    /// Whether to show line numbers
    public var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: "showLineNumbers") }
    }

    public init() {
        self.fontSize = UserDefaults.standard.object(forKey: "fontSize") as? CGFloat ?? 14.0
        self.fontFamily = UserDefaults.standard.string(forKey: "fontFamily")
        let themeRaw = UserDefaults.standard.string(forKey: "syntaxTheme") ?? SyntaxThemeSetting.xcodeDark.rawValue
        self.syntaxTheme = SyntaxThemeSetting(rawValue: themeRaw) ?? .xcodeDark
        let scaleRaw = UserDefaults.standard.string(forKey: "headingScale") ?? HeadingScaleSetting.normal.rawValue
        self.headingScale = HeadingScaleSetting(rawValue: scaleRaw) ?? .normal
        self.showLineNumbers = UserDefaults.standard.bool(forKey: "showLineNumbers")
    }
}

/// Behavior settings (link handling, interactions)
@MainActor
@Observable
public final class BehaviorSettings {
    /// How to handle clicked links
    public var linkBehavior: LinkBehavior {
        didSet { UserDefaults.standard.set(linkBehavior.rawValue, forKey: "linkBehavior") }
    }

    /// Whether to underline links
    public var underlineLinks: Bool {
        didSet { UserDefaults.standard.set(underlineLinks, forKey: "underlineLinks") }
    }

    public init() {
        let linkRaw = UserDefaults.standard.string(forKey: "linkBehavior") ?? LinkBehavior.browser.rawValue
        self.linkBehavior = LinkBehavior(rawValue: linkRaw) ?? .browser
        // Default underlineLinks to true if not set
        if UserDefaults.standard.object(forKey: "underlineLinks") == nil {
            self.underlineLinks = true
        } else {
            self.underlineLinks = UserDefaults.standard.bool(forKey: "underlineLinks")
        }
    }
}

// MARK: - Setting Types

/// Syntax theme options (mirrors aimdRenderer themes)
public enum SyntaxThemeSetting: String, CaseIterable, Identifiable, Sendable {
    case xcodeLight = "Xcode Light"
    case xcodeDark = "Xcode Dark"
    case githubLight = "GitHub Light"
    case githubDark = "GitHub Dark"
    case oneDark = "One Dark"
    case dracula = "Dracula"
    case solarizedLight = "Solarized Light"
    case solarizedDark = "Solarized Dark"
    case monokai = "Monokai"
    case nord = "Nord"

    public var id: String { rawValue }

    public var isDark: Bool {
        switch self {
        case .xcodeLight, .githubLight, .solarizedLight:
            return false
        case .xcodeDark, .githubDark, .oneDark, .dracula, .solarizedDark, .monokai, .nord:
            return true
        }
    }
}

/// Heading scale options
public enum HeadingScaleSetting: String, CaseIterable, Identifiable, Sendable {
    case compact
    case normal
    case spacious

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .normal: return "Normal"
        case .spacious: return "Spacious"
        }
    }
}

/// Link behavior options
public enum LinkBehavior: String, CaseIterable, Identifiable, Sendable {
    case browser
    case inApp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .browser: return "Open in Browser"
        case .inApp: return "Open in App"
        }
    }
}

// MARK: - UserDefaults Implementation

/// Default implementation using UserDefaults for persistence.
@MainActor
public final class UserDefaultsSettingsRepository: SettingsRepository {
    public var appearance: AppearanceSettings
    public var rendering: RenderingSettings
    public var behavior: BehaviorSettings

    public init() {
        self.appearance = AppearanceSettings()
        self.rendering = RenderingSettings()
        self.behavior = BehaviorSettings()
    }

    /// Shared instance for convenience
    public static let shared = UserDefaultsSettingsRepository()
}

// MARK: - Environment Key

/// Environment key for accessing settings repository
@MainActor
private struct SettingsRepositoryKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: SettingsRepository = {
        MainActor.assumeIsolated {
            UserDefaultsSettingsRepository.shared
        }
    }()
}

extension EnvironmentValues {
    @MainActor
    public var settings: SettingsRepository {
        get { self[SettingsRepositoryKey.self] }
        set { self[SettingsRepositoryKey.self] = newValue }
    }
}
