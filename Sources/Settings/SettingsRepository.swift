import SwiftUI
import aimdRenderer

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

// MARK: - Settings Containers (Pure Data)

/// Appearance settings (color scheme, theme).
/// Pure observable data — no persistence logic. Repository handles read/write.
@MainActor
@Observable
public final class AppearanceSettings {
    /// Color scheme preference (nil = follow system)
    public var colorScheme: ColorScheme? = nil

    public init() {}
}

/// Markdown rendering settings.
/// Pure observable data — no persistence logic. Repository handles read/write.
@MainActor
@Observable
public final class RenderingSettings {
    /// Base font size in points
    public var fontSize: CGFloat = 14.0

    /// Font family name (nil = system default)
    public var fontFamily: String? = nil

    /// Syntax highlighting theme
    public var syntaxTheme: SyntaxThemeSetting = .xcode

    /// Heading size scale
    public var headingScale: HeadingScaleSetting = .normal

    /// Whether to show line numbers
    public var showLineNumbers: Bool = false

    public init() {}
}

/// Behavior settings (link handling, interactions).
/// Pure observable data — no persistence logic. Repository handles read/write.
@MainActor
@Observable
public final class BehaviorSettings {
    /// How to handle clicked links
    public var linkBehavior: LinkBehavior = .browser

    /// Whether to underline links
    public var underlineLinks: Bool = true

    public init() {}
}

// MARK: - Setting Types

/// Syntax theme family — user picks a family, light/dark variant auto-resolves from appearance.
public enum SyntaxThemeSetting: String, CaseIterable, Identifiable, Sendable {
    case xcode = "Xcode"
    case github = "GitHub"
    case solarized = "Solarized"
    case oneDark = "One Dark"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case nord = "Nord"

    public var id: String { rawValue }

    /// Whether this family has distinct light/dark variants
    public var hasLightVariant: Bool {
        switch self {
        case .xcode, .github, .solarized: return true
        case .oneDark, .dracula, .monokai, .nord: return false
        }
    }

    /// Resolves the concrete aimdRenderer theme based on current appearance.
    /// Dark-only families always return their dark theme regardless of appearance.
    public func rendererTheme(isDark: Bool) -> SyntaxTheme {
        switch self {
        case .xcode:     return isDark ? .xcodeDark : .xcodeLight
        case .github:    return isDark ? .githubDark : .githubLight
        case .solarized: return isDark ? .solarizedDark : .solarizedLight
        case .oneDark:   return .oneDark
        case .dracula:   return .dracula
        case .monokai:   return .monokai
        case .nord:      return .nord
        }
    }

    /// Convenience: resolve from a ColorScheme (nil = dark default)
    public func rendererTheme(for colorScheme: ColorScheme?) -> SyntaxTheme {
        rendererTheme(isDark: colorScheme != .light)
    }

    // MARK: - Migration from old per-variant raw values

    /// Initializes from legacy raw values ("Xcode Dark", "GitHub Light", etc.)
    public init(migrating rawValue: String) {
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

    /// Converts to the MarkdownHighlighter's HeadingScale enum
    var highlighterScale: MarkdownHighlighter.HeadingScale {
        switch self {
        case .compact: return .compact
        case .normal: return .normal
        case .spacious: return .spacious
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
/// This is the only type that touches UserDefaults for settings.
/// It loads saved values on init and persists changes via didSet observers.
@MainActor
@Observable
public final class UserDefaultsSettingsRepository: SettingsRepository {
    public var appearance: AppearanceSettings {
        didSet { persistAppearance() }
    }
    public var rendering: RenderingSettings {
        didSet { persistRendering() }
    }
    public var behavior: BehaviorSettings {
        didSet { persistBehavior() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Create pure-data containers
        let appearance = AppearanceSettings()
        let rendering = RenderingSettings()
        let behavior = BehaviorSettings()

        // Load persisted values into containers
        if let raw = defaults.string(forKey: "colorScheme") {
            appearance.colorScheme = raw == "dark" ? .dark : .light
        }

        rendering.fontSize = defaults.object(forKey: "fontSize") as? CGFloat ?? 14.0
        rendering.fontFamily = defaults.string(forKey: "fontFamily")
        let themeRaw = defaults.string(forKey: "syntaxTheme") ?? SyntaxThemeSetting.xcode.rawValue
        rendering.syntaxTheme = SyntaxThemeSetting(rawValue: themeRaw) ?? SyntaxThemeSetting(migrating: themeRaw)
        let scaleRaw = defaults.string(forKey: "headingScale") ?? HeadingScaleSetting.normal.rawValue
        rendering.headingScale = HeadingScaleSetting(rawValue: scaleRaw) ?? .normal
        rendering.showLineNumbers = defaults.bool(forKey: "showLineNumbers")

        let linkRaw = defaults.string(forKey: "linkBehavior") ?? LinkBehavior.browser.rawValue
        behavior.linkBehavior = LinkBehavior(rawValue: linkRaw) ?? .browser
        if defaults.object(forKey: "underlineLinks") == nil {
            behavior.underlineLinks = true
        } else {
            behavior.underlineLinks = defaults.bool(forKey: "underlineLinks")
        }

        self.appearance = appearance
        self.rendering = rendering
        self.behavior = behavior

        // Start observing changes for persistence
        startObserving()
    }

    /// Shared instance for convenience
    public static let shared = UserDefaultsSettingsRepository()

    // MARK: - Persistence

    private func persistAppearance() {
        if let scheme = appearance.colorScheme {
            defaults.set(scheme == .dark ? "dark" : "light", forKey: "colorScheme")
        } else {
            defaults.removeObject(forKey: "colorScheme")
        }
    }

    private func persistRendering() {
        defaults.set(rendering.fontSize, forKey: "fontSize")
        if let family = rendering.fontFamily {
            defaults.set(family, forKey: "fontFamily")
        } else {
            defaults.removeObject(forKey: "fontFamily")
        }
        defaults.set(rendering.syntaxTheme.rawValue, forKey: "syntaxTheme")
        defaults.set(rendering.headingScale.rawValue, forKey: "headingScale")
        defaults.set(rendering.showLineNumbers, forKey: "showLineNumbers")
    }

    private func persistBehavior() {
        defaults.set(behavior.linkBehavior.rawValue, forKey: "linkBehavior")
        defaults.set(behavior.underlineLinks, forKey: "underlineLinks")
    }

    /// Observes property changes on settings containers and persists them.
    /// Uses withObservationTracking to re-arm after each change.
    private func startObserving() {
        observeAppearance()
        observeRendering()
        observeBehavior()
    }

    private func observeAppearance() {
        withObservationTracking {
            _ = appearance.colorScheme
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.persistAppearance()
                self?.observeAppearance()
            }
        }
    }

    private func observeRendering() {
        withObservationTracking {
            _ = rendering.fontSize
            _ = rendering.fontFamily
            _ = rendering.syntaxTheme
            _ = rendering.headingScale
            _ = rendering.showLineNumbers
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.persistRendering()
                self?.observeRendering()
            }
        }
    }

    private func observeBehavior() {
        withObservationTracking {
            _ = behavior.linkBehavior
            _ = behavior.underlineLinks
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.persistBehavior()
                self?.observeBehavior()
            }
        }
    }

}

// MARK: - Environment Key

/// Environment key for accessing settings repository
/// Note: Returns concrete type for SwiftUI Environment compatibility
// @preconcurrency required: EnvironmentKey.defaultValue lacks @MainActor annotation.
// Safe because SwiftUI accesses this on @MainActor view update path.
// TODO: Consider decomposing aggregated settings repository into domain-specific
// repositories (AppearanceSettings, BehaviorSettings) if the file grows beyond
// its current scope. Also consider removing SwiftUI import coupling in the future.
private struct SettingsRepositoryKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = UserDefaultsSettingsRepository.shared
}

extension EnvironmentValues {
    @MainActor
    public var settings: UserDefaultsSettingsRepository {
        get { self[SettingsRepositoryKey.self] }
        set { self[SettingsRepositoryKey.self] = newValue }
    }
}
