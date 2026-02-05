import Foundation

// MARK: - Syntax Theme

/// Enumeration of available syntax highlighting color schemes
public enum SyntaxTheme: String, Sendable, CaseIterable, Identifiable {
    // Apple themes
    case xcodeLight = "Xcode Light"
    case xcodeDark = "Xcode Dark"

    // GitHub themes
    case githubLight = "GitHub Light"
    case githubDark = "GitHub Dark"

    // Popular editor themes
    case oneDark = "One Dark"
    case dracula = "Dracula"
    case solarizedLight = "Solarized Light"
    case solarizedDark = "Solarized Dark"
    case monokai = "Monokai"
    case nord = "Nord"

    public var id: String { rawValue }

    /// Returns the color palette for this theme
    public var palette: SyntaxPalette {
        switch self {
        case .xcodeLight:
            return .xcodeLight
        case .xcodeDark:
            return .xcodeDark
        case .githubLight:
            return .githubLight
        case .githubDark:
            return .githubDark
        case .oneDark:
            return .oneDark
        case .dracula:
            return .dracula
        case .solarizedLight:
            return .solarizedLight
        case .solarizedDark:
            return .solarizedDark
        case .monokai:
            return .monokai
        case .nord:
            return .nord
        }
    }

    /// Whether this is a dark theme
    public var isDark: Bool {
        switch self {
        case .xcodeLight, .githubLight, .solarizedLight:
            return false
        case .xcodeDark, .githubDark, .oneDark, .dracula, .solarizedDark, .monokai, .nord:
            return true
        }
    }
}

// MARK: - Syntax Palette

/// Color palette for syntax highlighting
/// Uses hex strings for cross-platform compatibility
public struct SyntaxPalette: Sendable, Equatable {

    // MARK: - Base Colors

    /// Background color
    public let background: String

    /// Default text color
    public let foreground: String

    /// Selection highlight color
    public let selection: String

    /// Line number color
    public let lineNumber: String

    // MARK: - Syntax Colors

    /// Keywords (if, let, func, etc.)
    public let keyword: String

    /// Strings ("hello", """multiline""")
    public let string: String

    /// Comments (// and /* */)
    public let comment: String

    /// Numbers (42, 3.14)
    public let number: String

    /// Types (String, Int, MyClass)
    public let type: String

    /// Functions and method names
    public let function: String

    /// Properties and variables
    public let property: String

    /// Operators (+, -, ==, etc.)
    public let `operator`: String

    /// Preprocessor / directives (#if, @main)
    public let preprocessor: String

    public init(
        background: String,
        foreground: String,
        selection: String,
        lineNumber: String,
        keyword: String,
        string: String,
        comment: String,
        number: String,
        type: String,
        function: String,
        property: String,
        `operator`: String,
        preprocessor: String
    ) {
        self.background = background
        self.foreground = foreground
        self.selection = selection
        self.lineNumber = lineNumber
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.type = type
        self.function = function
        self.property = property
        self.operator = `operator`
        self.preprocessor = preprocessor
    }
}

// MARK: - Built-in Palettes

extension SyntaxPalette {

    // MARK: - Xcode Light

    public static let xcodeLight = SyntaxPalette(
        background: "#FFFFFF",
        foreground: "#000000",
        selection: "#B4D8FD",
        lineNumber: "#A8A8A8",
        keyword: "#9B2393",
        string: "#D12F1B",
        comment: "#5D6C79",
        number: "#272AD8",
        type: "#3900A0",
        function: "#0F68A0",
        property: "#326D74",
        operator: "#000000",
        preprocessor: "#78492A"
    )

    // MARK: - Xcode Dark

    public static let xcodeDark = SyntaxPalette(
        background: "#1F1F24",
        foreground: "#FFFFFF",
        selection: "#515B70",
        lineNumber: "#6C6C6C",
        keyword: "#FF7AB2",
        string: "#FF8170",
        comment: "#7F8C98",
        number: "#D0BF69",
        type: "#ACF2E4",
        function: "#67B7A4",
        property: "#5DD8FF",
        operator: "#FFFFFF",
        preprocessor: "#FFA14F"
    )

    // MARK: - GitHub Light

    public static let githubLight = SyntaxPalette(
        background: "#FFFFFF",
        foreground: "#24292E",
        selection: "#C8C8FA",
        lineNumber: "#959DA5",
        keyword: "#D73A49",
        string: "#032F62",
        comment: "#6A737D",
        number: "#005CC5",
        type: "#6F42C1",
        function: "#6F42C1",
        property: "#005CC5",
        operator: "#D73A49",
        preprocessor: "#D73A49"
    )

    // MARK: - GitHub Dark

    public static let githubDark = SyntaxPalette(
        background: "#0D1117",
        foreground: "#C9D1D9",
        selection: "#3B5070",
        lineNumber: "#6E7681",
        keyword: "#FF7B72",
        string: "#A5D6FF",
        comment: "#8B949E",
        number: "#79C0FF",
        type: "#FFA657",
        function: "#D2A8FF",
        property: "#79C0FF",
        operator: "#FF7B72",
        preprocessor: "#FF7B72"
    )

    // MARK: - One Dark

    public static let oneDark = SyntaxPalette(
        background: "#282C34",
        foreground: "#ABB2BF",
        selection: "#3E4451",
        lineNumber: "#4B5263",
        keyword: "#C678DD",
        string: "#98C379",
        comment: "#5C6370",
        number: "#D19A66",
        type: "#E5C07B",
        function: "#61AFEF",
        property: "#E06C75",
        operator: "#56B6C2",
        preprocessor: "#C678DD"
    )

    // MARK: - Dracula

    public static let dracula = SyntaxPalette(
        background: "#282A36",
        foreground: "#F8F8F2",
        selection: "#44475A",
        lineNumber: "#6272A4",
        keyword: "#FF79C6",
        string: "#F1FA8C",
        comment: "#6272A4",
        number: "#BD93F9",
        type: "#8BE9FD",
        function: "#50FA7B",
        property: "#FFB86C",
        operator: "#FF79C6",
        preprocessor: "#FF79C6"
    )

    // MARK: - Solarized Light

    public static let solarizedLight = SyntaxPalette(
        background: "#FDF6E3",
        foreground: "#657B83",
        selection: "#EEE8D5",
        lineNumber: "#93A1A1",
        keyword: "#859900",
        string: "#2AA198",
        comment: "#93A1A1",
        number: "#D33682",
        type: "#B58900",
        function: "#268BD2",
        property: "#CB4B16",
        operator: "#657B83",
        preprocessor: "#CB4B16"
    )

    // MARK: - Solarized Dark

    public static let solarizedDark = SyntaxPalette(
        background: "#002B36",
        foreground: "#839496",
        selection: "#073642",
        lineNumber: "#586E75",
        keyword: "#859900",
        string: "#2AA198",
        comment: "#586E75",
        number: "#D33682",
        type: "#B58900",
        function: "#268BD2",
        property: "#CB4B16",
        operator: "#839496",
        preprocessor: "#CB4B16"
    )

    // MARK: - Monokai

    public static let monokai = SyntaxPalette(
        background: "#272822",
        foreground: "#F8F8F2",
        selection: "#49483E",
        lineNumber: "#90908A",
        keyword: "#F92672",
        string: "#E6DB74",
        comment: "#75715E",
        number: "#AE81FF",
        type: "#66D9EF",
        function: "#A6E22E",
        property: "#FD971F",
        operator: "#F92672",
        preprocessor: "#F92672"
    )

    // MARK: - Nord

    public static let nord = SyntaxPalette(
        background: "#2E3440",
        foreground: "#D8DEE9",
        selection: "#434C5E",
        lineNumber: "#4C566A",
        keyword: "#81A1C1",
        string: "#A3BE8C",
        comment: "#616E88",
        number: "#B48EAD",
        type: "#8FBCBB",
        function: "#88C0D0",
        property: "#D8DEE9",
        operator: "#81A1C1",
        preprocessor: "#5E81AC"
    )
}
