import SwiftUI
import AppKit
import aimdRenderer

// MARK: - Configuration

/// Configuration for markdown text handling
/// OOD: Shared, observable configuration that can be modified from multiple places
enum MarkdownConfig {
    /// Maximum allowed text size (10MB) to prevent DoS attacks
    /// Accessible from any context without actor isolation
    static let maxTextSize = 10_485_760

    /// Maximum text size for syntax highlighting (1MB)
    /// Files larger than this show plain text
    static let maxHighlightSize = 1_048_576
}

// MARK: - Custom NSTextView

/// NSTextView subclass that ensures the find bar can be dismissed with Esc
/// when hosted inside SwiftUI (SwiftUI can intercept key events before AppKit).
final class MarkdownNSTextView: NSTextView {
    override func cancelOperation(_ sender: Any?) {
        let hideItem = NSMenuItem()
        hideItem.tag = NSTextFinder.Action.hideFindInterface.rawValue
        performFindPanelAction(hideItem)
    }
}

// MARK: - Markdown Editor

/// NSTextView wrapper with Markdown syntax highlighting.
/// Now uses aimdRenderer's SyntaxTheme system through SettingsRepository.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.settings) private var settings

    /// Callback for reporting errors (optional)
    var onError: ((AppError) -> Void)? = nil

    /// Callback when scroll position changes (0.0–1.0)
    var onScrollPositionChanged: ((Double) -> Void)? = nil

    /// Scroll position to restore (0.0–1.0), set once after content loads
    var restoreScrollPosition: Double? = nil

    /// Bookmarked line numbers (1-based) to display in the gutter
    var bookmarkedLines: Set<Int> = []

    /// Called when user clicks gutter to toggle a bookmark at a line
    var onToggleBookmark: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        // Manual TextKit stack so we can use our custom NSTextView subclass
        // (MarkdownNSTextView handles Esc to dismiss the find bar in SwiftUI)
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownNSTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // Configure text view (read-only viewer)
        textView.isEditable = false
        textView.isRichText = false

        // Get theme colors from settings (resolve light/dark variant from appearance)
        let syntaxTheme = settings.rendering.syntaxTheme.rendererTheme(for: settings.appearance.colorScheme)
        let palette = syntaxTheme.palette

        // Apply user preferences with theme colors
        let fontSize = settings.rendering.fontSize
        textView.font = MarkdownHighlighter.resolveFont(family: settings.rendering.fontFamily, size: fontSize, weight: .regular)
        textView.textColor = NSColor(hex: palette.foreground) ?? .labelColor
        textView.backgroundColor = NSColor(hex: palette.background) ?? .textBackgroundColor
        textView.insertionPointColor = NSColor(hex: palette.foreground) ?? .labelColor

        // We manage theme colors explicitly — don't let AppKit remap them
        textView.usesAdaptiveColorMappingForDarkAppearance = false

        // Scale insets proportionally with font size (base 16pt at font size 14)
        let insetScale = max(1.0, fontSize / 14.0)
        let scaledInset = round(16.0 * insetScale)
        textView.textContainerInset = NSSize(width: scaledInset, height: scaledInset)

        // Native find bar (Cmd+F) with incremental search
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Link appearance — theme color with optional underline
        var linkAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(hex: palette.function) ?? .systemTeal,
            .cursor: NSCursor.pointingHand
        ]
        if settings.behavior.underlineLinks {
            linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        textView.linkTextAttributes = linkAttrs

        // Line numbers + bookmarks
        let lineNumberView = LineNumberRulerView(textView: textView)
        lineNumberView.bookmarkedLines = bookmarkedLines
        lineNumberView.onToggleBookmark = onToggleBookmark
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = settings.rendering.showLineNumbers

        // Accessibility
        textView.setAccessibilityElement(true)
        textView.setAccessibilityLabel("Markdown document viewer")
        textView.setAccessibilityRole(.textArea)
        textView.setAccessibilityHelp("Read-only markdown content with syntax highlighting. Use Cmd+F to search.")

        // Delegate
        textView.delegate = context.coordinator

        // Scroll position tracking
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Initial content
        context.coordinator.applyHighlighting(to: textView, text: text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let currentFontSize = settings.rendering.fontSize
        let currentTheme = settings.rendering.syntaxTheme
        let currentFontFamily = settings.rendering.fontFamily
        let currentHeadingScale = settings.rendering.headingScale
        let currentColorScheme = settings.appearance.colorScheme

        // Check if any rendering settings changed
        let fontChanged = context.coordinator.fontSize != currentFontSize
        let themeChanged = context.coordinator.syntaxTheme != currentTheme
        let fontFamilyChanged = context.coordinator.fontFamily != currentFontFamily
        let headingScaleChanged = context.coordinator.headingScale != currentHeadingScale
        let appearanceChanged = context.coordinator.colorScheme != currentColorScheme

        if fontChanged || themeChanged || fontFamilyChanged || headingScaleChanged || appearanceChanged {
            // Update settings and recreate highlighter
            context.coordinator.updateSettings(fontSize: currentFontSize, theme: currentTheme, fontFamily: currentFontFamily, headingScale: currentHeadingScale, colorScheme: currentColorScheme)

            // Update text view colors
            let palette = currentTheme.rendererTheme(for: currentColorScheme).palette
            textView.textColor = NSColor(hex: palette.foreground) ?? .labelColor
            textView.backgroundColor = NSColor(hex: palette.background) ?? .textBackgroundColor
            textView.insertionPointColor = NSColor(hex: palette.foreground) ?? .labelColor

            // Update link appearance
            var linkAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(hex: palette.function) ?? .systemTeal,
                .cursor: NSCursor.pointingHand
            ]
            if settings.behavior.underlineLinks {
                linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            textView.linkTextAttributes = linkAttrs

            // Re-apply highlighting with new settings
            context.coordinator.applyHighlighting(to: textView, text: text)
        }

        // Re-apply highlighting if text changed externally (but settings didn't)
        else if textView.string != text {
            context.coordinator.applyHighlighting(to: textView, text: text)

            // Restore scroll position after content loads
            if let position = restoreScrollPosition {
                context.coordinator.restoreScrollPosition(position, in: scrollView)
            }
        }

        // Update scroll callback reference
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged

        // Toggle line numbers + update bookmarks
        scrollView.rulersVisible = settings.rendering.showLineNumbers
        if let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
            ruler.bookmarkedLines = bookmarkedLines
            ruler.onToggleBookmark = onToggleBookmark
            ruler.needsDisplay = true
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = nil
        }
        NotificationCenter.default.removeObserver(coordinator)
    }

    func makeCoordinator() -> Coordinator {
        let fontSize = settings.rendering.fontSize
        let syntaxTheme = settings.rendering.syntaxTheme
        let fontFamily = settings.rendering.fontFamily
        let headingScale = settings.rendering.headingScale
        let colorScheme = settings.appearance.colorScheme
        return Coordinator(self, fontSize: fontSize, syntaxTheme: syntaxTheme, fontFamily: fontFamily, headingScale: headingScale, colorScheme: colorScheme, onError: onError)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        private var debouncedHighlighter: DebouncedHighlighter
        private var isUpdating = false
        var onScrollPositionChanged: ((Double) -> Void)?
        var fontSize: CGFloat
        var syntaxTheme: SyntaxThemeSetting
        var fontFamily: String?
        var headingScale: HeadingScaleSetting
        var colorScheme: ColorScheme?
        var onError: ((AppError) -> Void)?

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        init(_ parent: MarkdownEditor, fontSize: CGFloat, syntaxTheme: SyntaxThemeSetting, fontFamily: String? = nil, headingScale: HeadingScaleSetting = .normal, colorScheme: ColorScheme? = nil, onError: ((AppError) -> Void)? = nil) {
            self.parent = parent
            self.fontSize = fontSize
            self.syntaxTheme = syntaxTheme
            self.fontFamily = fontFamily
            self.headingScale = headingScale
            self.colorScheme = colorScheme
            self.onError = onError
            let resolved = syntaxTheme.rendererTheme(for: colorScheme)
            let highlighter = MarkdownHighlighter(syntaxTheme: resolved, fontSize: fontSize, fontFamily: fontFamily, headingScale: headingScale.highlighterScale)
            self.debouncedHighlighter = DebouncedHighlighter(highlighter: highlighter, debounceDelay: .milliseconds(150))
        }

        func updateSettings(fontSize: CGFloat, theme: SyntaxThemeSetting, fontFamily: String? = nil, headingScale: HeadingScaleSetting = .normal, colorScheme: ColorScheme? = nil) {
            self.fontSize = fontSize
            self.syntaxTheme = theme
            self.fontFamily = fontFamily
            self.headingScale = headingScale
            self.colorScheme = colorScheme
            let resolved = theme.rendererTheme(for: colorScheme)
            let newHighlighter = MarkdownHighlighter(syntaxTheme: resolved, fontSize: fontSize, fontFamily: fontFamily, headingScale: headingScale.highlighterScale)
            debouncedHighlighter = DebouncedHighlighter(highlighter: newHighlighter, debounceDelay: .milliseconds(150))
        }

        func applyHighlighting(to textView: NSTextView, text: String) {
            guard !isUpdating else { return }

            // Security: Prevent DoS from extremely large files
            guard text.utf8.count <= MarkdownConfig.maxTextSize else {
                onError?(.textSizeExceeded)
                return
            }

            isUpdating = true
            let selectedRanges = textView.selectedRanges

            // Highlight synchronously — the debounced highlighter already coalesces rapid updates.
            // NSAttributedString isn't Sendable on macOS, so offloading to Task.detached
            // would require unsafe transfers. Highlighting is fast enough on-main-actor.
            let attributed = debouncedHighlighter.highlighter.highlight(text)
            textView.textStorage?.setAttributedString(attributed)
            textView.selectedRanges = selectedRanges
            isUpdating = false
        }

        nonisolated func textDidChange(_ notification: Notification) {
            // Extract NSTextView before crossing isolation boundary
            guard let textView = notification.object as? NSTextView else { return }

            // AppKit always calls delegate methods on the main thread,
            // so we can safely assume MainActor isolation
            MainActor.assumeIsolated {
                guard !isUpdating else { return }

                let textContent = textView.string

                // Security: Prevent DoS from extremely large files
                guard textContent.utf8.count <= MarkdownConfig.maxTextSize else {
                    onError?(.textSizeExceeded)
                    return
                }

                // Update parent binding synchronously (no Task overhead)
                parent.text = textContent

                // Use debounced highlighting for better performance
                debouncedHighlighter.highlightDebounced(textContent) { [weak self, weak textView] attributed in
                    guard let self, let textView else { return }
                    guard !self.isUpdating else { return }

                    self.isUpdating = true
                    defer { self.isUpdating = false }

                    let selectedRanges = textView.selectedRanges
                    textView.textStorage?.setAttributedString(attributed)
                    textView.selectedRanges = selectedRanges
                }
            }
        }

        // MARK: - Link Handling

        nonisolated func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }

            return MainActor.assumeIsolated {
                if url.scheme == nil, let fragment = url.fragment {
                    // Fragment-only link (e.g. #heading) — scroll to matching heading
                    scrollToHeading(fragment: fragment, in: textView)
                    return true
                } else if url.scheme != nil {
                    // External link — open in default browser
                    NSWorkspace.shared.open(url)
                    return true
                }
                // Malformed link (no scheme, no fragment) — ignore gracefully
                return false
            }
        }

        /// Scrolls to the heading whose GitHub-style slug matches the given fragment.
        private func scrollToHeading(fragment: String, in textView: NSTextView) {
            let text = textView.string
            let lines = text.components(separatedBy: .newlines)
            var searchOffset = 0

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    // Strip leading # characters and whitespace to get heading text
                    let headingText = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    if Self.slugify(headingText) == fragment.lowercased() {
                        let nsString = text as NSString
                        let lineRange = nsString.range(of: line, range: NSRange(location: searchOffset, length: nsString.length - searchOffset))
                        guard lineRange.location != NSNotFound else { continue }

                        textView.scrollRangeToVisible(lineRange)
                        textView.showFindIndicator(for: lineRange)
                        return
                    }
                }
                // Advance offset past this line + newline
                searchOffset += line.utf16.count + 1
            }
        }

        /// Converts heading text to a GitHub-style slug for anchor matching.
        /// Lowercases, replaces spaces with hyphens, strips non-alphanumeric (except hyphens).
        static func slugify(_ text: String) -> String {
            text.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
                .reduce(into: "") { $0.unicodeScalars.append($1) }
        }

        // MARK: - Scroll Position

        @objc nonisolated func scrollViewDidScroll(_ notification: Notification) {
            // AppKit delivers boundsDidChange on the main thread.
            // nonisolated(unsafe) required: notification.object is Any? (not Sendable),
            // but we immediately enter MainActor.assumeIsolated — no actual cross-thread access.
            nonisolated(unsafe) let object = notification.object
            MainActor.assumeIsolated {
                guard let clipView = object as? NSClipView,
                      let documentView = clipView.documentView else { return }

                let contentHeight = documentView.frame.height
                let visibleHeight = clipView.bounds.height
                let scrollableHeight = contentHeight - visibleHeight
                guard scrollableHeight > 0 else { return }

                let position = clipView.bounds.origin.y / scrollableHeight
                let clamped = min(max(position, 0.0), 1.0)
                onScrollPositionChanged?(clamped)
            }
        }

        func restoreScrollPosition(_ position: Double, in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }

            // Defer to next layout pass so text is fully laid out
            Task { @MainActor in
                let contentHeight = documentView.frame.height
                let visibleHeight = scrollView.contentView.bounds.height
                let scrollableHeight = contentHeight - visibleHeight
                guard scrollableHeight > 0 else { return }

                let yOffset = position * scrollableHeight
                documentView.scroll(NSPoint(x: 0, y: yOffset))
            }
        }
    }
}
