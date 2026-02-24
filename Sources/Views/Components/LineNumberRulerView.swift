import AppKit

/// Line number gutter for NSTextView with bookmark support.
/// Shows line numbers and bookmark indicators. Click to toggle bookmarks.
final class LineNumberRulerView: NSRulerView {

    private weak var textView: NSTextView?

    /// Set of bookmarked line numbers (1-based)
    var bookmarkedLines: Set<Int> = [] {
        didSet { needsDisplay = true }
    }

    /// Called when user clicks a line to toggle bookmark
    var onToggleBookmark: ((Int) -> Void)?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40

        // Decorative element — VoiceOver should skip this ruler.
        // Line numbers are visual context, not meaningful content for screen readers.
        setAccessibilityElement(false)
        setAccessibilityRole(.unknown)

        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    // MARK: - Click to Toggle Bookmark

    override func mouseDown(with event: NSEvent) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            super.mouseDown(with: event)
            return
        }

        let clickPoint = convert(event.locationInWindow, from: nil)
        // Convert to text view coordinates
        let textPoint = NSPoint(
            x: 0,
            y: clickPoint.y + textView.visibleRect.origin.y - textView.textContainerInset.height
        )

        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let text = textView.string as NSString

        // Count line number at click position
        var lineNumber = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: min(charIndex, text.length)), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        onToggleBookmark?(lineNumber)
    }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let text = textView.string as NSString
        let inset = textView.textContainerInset

        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let bookmarkAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.systemOrange,
        ]

        // Count lines up to visible range start
        var lineNumber = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: characterRange.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        // Draw line numbers for visible lines
        text.enumerateSubstrings(in: characterRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            lineRect.origin.y += inset.height - visibleRect.origin.y

            let isBookmarked = self.bookmarkedLines.contains(lineNumber)
            let attrs = isBookmarked ? bookmarkAttrs : numberAttrs

            // Draw bookmark dot for bookmarked lines
            if isBookmarked {
                let dotSize: CGFloat = 6
                let dotRect = NSRect(
                    x: 3,
                    y: lineRect.origin.y + (lineRect.height - dotSize) / 2,
                    width: dotSize,
                    height: dotSize
                )
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            let numStr = "\(lineNumber)" as NSString
            let size = numStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: self.ruleThickness - size.width - 6,
                y: lineRect.origin.y + (lineRect.height - size.height) / 2
            )
            numStr.draw(at: drawPoint, withAttributes: attrs)
            lineNumber += 1
        }
    }
}
