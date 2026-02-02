import SwiftUI
import AppKit

/// NSTextView wrapper with Markdown syntax highlighting
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Configure text view
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
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

        // Only update if text changed externally
        if textView.string != text {
            context.coordinator.applyHighlighting(to: textView, text: text)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        let highlighter = MarkdownHighlighter()
        private var isUpdating = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func applyHighlighting(to textView: NSTextView, text: String) {
            guard !isUpdating else { return }
            isUpdating = true
            defer { isUpdating = false }

            let selectedRanges = textView.selectedRanges
            let attributed = highlighter.highlight(text)

            textView.textStorage?.setAttributedString(attributed)
            textView.selectedRanges = selectedRanges
        }

        nonisolated func textDidChange(_ notification: Notification) {
            // Extract NSTextView reference before crossing isolation boundary
            guard let textView = notification.object as? NSTextView else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !isUpdating else { return }

                parent.text = textView.string

                // Re-highlight (debounce this in production)
                applyHighlighting(to: textView, text: textView.string)
            }
        }
    }
}
