import SwiftUI
import AppKit

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

// MARK: - Markdown Editor

/// NSTextView wrapper with Markdown syntax highlighting
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @AppStorage("fontSize") private var fontSize: Double = 14.0

    /// Callback for reporting errors (optional)
    var onError: ((AppError) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Configure text view
        textView.isRichText = false
        textView.allowsUndo = true
        
        // Respect user preferences for text substitutions
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        
        // Apply user preferences
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor

        // Appearance
        textView.textContainerInset = NSSize(width: 16, height: 16)

        // Delegate
        textView.delegate = context.coordinator

        // Initial content
        context.coordinator.applyHighlighting(to: textView, text: text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Check if font size changed
        let fontChanged = context.coordinator.fontSize != fontSize
        
        if fontChanged {
            // Update font size and recreate highlighter
            context.coordinator.updateFontSize(fontSize)
            // Re-apply highlighting with new font size
            context.coordinator.applyHighlighting(to: textView, text: text)
        }
        
        // Re-apply highlighting if text changed externally (but font didn't)
        else if textView.string != text {
            context.coordinator.applyHighlighting(to: textView, text: text)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, fontSize: fontSize, onError: onError)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        private var debouncedHighlighter: DebouncedHighlighter
        private var isUpdating = false
        var fontSize: Double
        var onError: ((AppError) -> Void)?

        init(_ parent: MarkdownEditor, fontSize: Double, onError: ((AppError) -> Void)? = nil) {
            self.parent = parent
            self.fontSize = fontSize
            self.onError = onError
            let highlighter = MarkdownHighlighter(fontSize: fontSize)
            self.debouncedHighlighter = DebouncedHighlighter(highlighter: highlighter, debounceDelay: .milliseconds(150))
        }
        
        func updateFontSize(_ newSize: Double) {
            fontSize = newSize
            let newHighlighter = MarkdownHighlighter(fontSize: newSize)
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
            defer { isUpdating = false }

            let selectedRanges = textView.selectedRanges
            
            // Apply syntax highlighting synchronously using the debounced highlighter's instance
            let attributed = debouncedHighlighter.highlighter.highlight(text)
            textView.textStorage?.setAttributedString(attributed)

            textView.selectedRanges = selectedRanges
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
    }
}
