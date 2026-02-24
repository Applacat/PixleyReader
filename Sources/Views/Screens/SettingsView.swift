import SwiftUI

// MARK: - Settings View

/// Top-level settings window with tabbed navigation.
/// Opened via Cmd+, (macOS Settings scene).
struct SettingsView: View {

    var body: some View {
        TabView {
            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            BehaviorSettingsTab()
                .tabItem {
                    Label("Behavior", systemImage: "gearshape")
                }
        }
        // Fixed 480x400: Settings window sized for form readability. macOS handles zoom at OS level.
        .frame(width: 480, height: 400)
    }
}

// MARK: - Appearance Tab

/// Unified appearance: color scheme, theme, font, headings, line numbers.
/// Theme auto-syncs light/dark variant with the current color scheme.
struct AppearanceSettingsTab: View {

    @Environment(\.settings) private var settings

    /// Maps optional ColorScheme to a picker-friendly enum
    private enum SchemeChoice: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }
    }

    private var schemeChoice: SchemeChoice {
        switch settings.appearance.colorScheme {
        case nil: return .system
        case .light: return .light
        case .dark: return .dark
        default: return .system
        }
    }

    /// Font family options
    private enum FontFamilyChoice: String, CaseIterable, Identifiable {
        case system = "System Default"
        case serif = "Serif"
        case sansSerif = "Sans-Serif"
        case monospaced = "Monospaced"

        var id: String { rawValue }

        var familyName: String? {
            switch self {
            case .system: return nil
            case .serif: return "New York"
            case .sansSerif: return "SF Pro"
            case .monospaced: return "SF Mono"
            }
        }

        init(from familyName: String?) {
            switch familyName {
            case nil: self = .system
            case "New York": self = .serif
            case "SF Pro": self = .sansSerif
            case "SF Mono": self = .monospaced
            default: self = .system
            }
        }
    }

    var body: some View {
        @Bindable var rendering = settings.rendering

        Form {
            // Color scheme
            Picker("Color Scheme", selection: Binding<SchemeChoice>(
                get: { schemeChoice },
                set: { newValue in
                    switch newValue {
                    case .system: settings.appearance.colorScheme = nil
                    case .light: settings.appearance.colorScheme = .light
                    case .dark: settings.appearance.colorScheme = .dark
                    }
                }
            )) {
                ForEach(SchemeChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            // Theme family (light/dark variant auto-resolves from color scheme)
            Picker("Theme", selection: $rendering.syntaxTheme) {
                ForEach(SyntaxThemeSetting.allCases) { theme in
                    Text("\(theme.rawValue) — \(theme.hasLightVariant ? "Light + Dark" : "Dark only")")
                        .tag(theme)
                }
            }

            // Font size
            HStack {
                Text("Font Size")
                Spacer()
                Text("\(Int(settings.rendering.fontSize)) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Slider(
                    value: $rendering.fontSize,
                    in: 10...32,
                    step: 1
                )
                .frame(width: 160)
            }

            // Font family
            Picker("Font Family", selection: Binding<FontFamilyChoice>(
                get: { FontFamilyChoice(from: settings.rendering.fontFamily) },
                set: { settings.rendering.fontFamily = $0.familyName }
            )) {
                ForEach(FontFamilyChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }

            // Heading scale
            Picker("Heading Scale", selection: $rendering.headingScale) {
                ForEach(HeadingScaleSetting.allCases) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .pickerStyle(.segmented)

            // Line numbers
            Toggle("Show Line Numbers", isOn: $rendering.showLineNumbers)
        }
        .formStyle(.grouped)
    }

    /// Indicator showing whether a theme has light+dark variants or is dark-only
    @ViewBuilder
    private func themeIndicator(_ theme: SyntaxThemeSetting) -> some View {
        HStack(spacing: 4) {
            if theme.hasLightVariant {
                // Half-and-half circle for themes with both variants
                ZStack {
                    Circle().fill(Color.white)
                    Circle().trim(from: 0.5, to: 1.0).fill(Color.black)
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                }
                .frame(width: 16, height: 16)
                Text("Light + Dark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.black)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    .frame(width: 16, height: 16)
                Text("Dark only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Behavior Tab

/// Link behavior and underline links
struct BehaviorSettingsTab: View {

    @Environment(\.settings) private var settings

    var body: some View {
        @Bindable var behavior = settings.behavior

        Form {
            Picker("Link Behavior", selection: $behavior.linkBehavior) {
                ForEach(LinkBehavior.allCases) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }

            Toggle("Underline Links", isOn: $behavior.underlineLinks)
        }
        .formStyle(.grouped)
    }
}
