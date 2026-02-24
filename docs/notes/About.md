# About Pixley Markdown Reader

**Version 1.0**  
A native macOS app for reading markdown files with style.

---

## What is Pixley Markdown Reader?

Pixley Markdown Reader is a lightweight, fast, and beautiful markdown viewer for macOS. It's designed to help you read AI-generated markdown files, documentation, notes, and any `.md` files with ease.

### Key Features

- **🎨 Beautiful Syntax Highlighting** — Markdown rendered with colors and styles
- **📁 Folder Navigation** — Browse entire directories of markdown files
- **⚡ Fast Performance** — Optimized for large files and quick navigation
- **🔒 Secure** — Security-scoped bookmarks, sandboxed, privacy-first
- **🌓 Dark Mode Support** — Looks great in light and dark themes

---

## Credits & Acknowledgments

### Markdown Highlighting

This app's syntax highlighting is powered by **custom NSRegularExpression patterns** designed specifically for markdown. The highlighting engine includes:

- Heading detection (# ## ###)
- Code block and inline code highlighting
- Bold and italic text styling
- Link and list styling
- Blockquote and separator detection

**Implementation:**
- Pattern-based regex matching
- Compiled patterns for performance
- Debounced rendering for smooth typing
- NSAttributedString styling

All markdown highlighting code was written in-house using Swift and AppKit's NSTextView.

### Technologies Used

- **Swift** — Apple's modern programming language
- **SwiftUI** — Declarative UI framework
- **AppKit** — NSTextView for text rendering
- **Swift Concurrency** — Actor-based isolation for thread safety
- **Foundation Models** (optional) — On-device AI for chat features

### Design Philosophy

Pixley Markdown Reader follows these principles:

1. **Native First** — Built with Apple's frameworks for the best macOS experience
2. **Performance Matters** — Debounced highlighting, size limits, efficient caching
3. **Security by Design** — File size limits (10MB), regex DoS prevention, sandboxed
4. **Object-Oriented Design** — Clean separation of concerns, testable components

---

## Open Source

Pixley Markdown Reader is built with love for the markdown community. We believe in:

- ✅ Native apps over web wrappers
- ✅ Privacy over data collection
- ✅ Performance over feature bloat
- ✅ Simplicity over complexity

---

## Version History

**1.0.0** (February 2026)
- Initial release
- Markdown syntax highlighting
- Folder navigation with NSOutlineView
- Font size controls
- Security-scoped bookmarks
- Welcome tutorial
- Performance optimizations (debouncing, caching)

---

## System Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon or Intel** processor
- **10 MB** free disk space

---

## Support

Need help? Here's how to get support:

- **Help Menu** → Pixley Markdown Reader Help
- **Report Bugs** → Help Menu → Report a Bug
- **Documentation** → Browse the Welcome folder files

---

## Privacy Policy

Pixley Markdown Reader **does not collect any data**. Your files stay on your device. The app requests permission to access:

- Folders you explicitly choose
- System folders (Desktop, Documents, Downloads) only with your permission

All file access uses macOS security-scoped bookmarks and follows Apple's sandboxing guidelines.

---

## Legal

© 2026 Pixley Markdown Reader  
All rights reserved.

Markdown syntax highlighting implementation is original work.  
No third-party markdown parsing libraries were used.

---

**Made with ❤️ for markdown lovers**

*Enjoy reading your markdown files in style!*
