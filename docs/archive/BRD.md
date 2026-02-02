# Pixley Reader - Business Requirements Document

**Version:** 1.0
**Date:** 2026-02-01
**Status:** APPROVED

---

## Vision

Pixley Reader is a native macOS companion app for developers working with AI tools. It monitors markdown files that AI writes and updates, providing a beautiful read-only view with live refresh and contextual AI chat.

**One sentence:** Watch what AI writes, ask questions about it, stay in flow.

---

## Target User

Developers who:
- Use CLI-based AI tools (Claude Code, Cursor, Copilot CLI)
- Generate markdown files (specs, docs, notes, journals)
- Want to monitor those files updating without switching context
- Need to quickly ask "what does this mean?" about AI-generated content

**Not for:** General markdown editing, note-taking, or document management.

---

## Core Problem

AI tools generate and update markdown files while you work. Currently you either:
1. `cat` the file repeatedly in terminal
2. Open in VS Code and manually refresh
3. Lose context switching between tools

Pixley Reader solves this by being a dedicated, beautiful, always-watching viewer.

---

## Three Features (v1.0)

### 1. Markdown Viewer

**What:** Read-only rendered markdown with syntax highlighting.

**Experience:**
- Headers, code blocks, links, lists, blockquotes, tables
- Liquid glass aesthetic (materials, blur, depth)
- Smooth scrolling, native feel
- No editing capability whatsoever

**Technical:** Uses preserved MarkdownHighlighter.swift with NSTextView wrapper.

---

### 2. Get Files In

**What:** Open files or folders via naturalization.

**Import flow:**
1. Drag folder to dock icon OR File → Open (supports folder selection)
2. Naturalization creates `.pixleyreader` package (security-scoped bookmark, not a copy)
3. DocumentGroup browser opens with **project name highlighted and editable**
4. Default name = original folder name, user can rename inline
5. Package persists in browser - import once, access forever

**Viewing flow:**
1. Open package from DocumentGroup browser
2. Three-column view shows live contents of original folder
3. File changes detected via DispatchSource
4. **Slack-style refresh pill:** "Content updated" floats up, tap to reload

**What persists:** Project packages in DocumentGroup (no re-import needed)
**What's ephemeral:** Viewing window state (scroll position, chat history)

**Also supports:**
- Direct .md file opening (no naturalization, opens viewer directly)
- Dock icon drops
- File importer dialog (File → Open, supports both files and folders)

---

### 3. AI Chat

**What:** Ask questions about the currently viewed document. All on-device.

**Experience:**
- Right panel in three-column layout
- Powered by Apple Foundation Models (on-device, private)
- Ask: "Summarize this" / "What does step 3 mean?" / "What changed?"
- Ephemeral - no history between sessions
- Plain text responses

**Constraints:**
- Only about THIS document (not general assistant)
- 4,096 token context window (~12K characters) - truncate longer docs
- No persistence between sessions
- Check availability before use (device eligibility, Apple Intelligence enabled)

**Technical:** Apple Foundation Models framework:
```swift
import FoundationModels

// Check availability first
guard SystemLanguageModel.default.availability == .available else {
    // Show "Requires Apple Intelligence" message
    return
}

let session = LanguageModelSession(instructions: "Answer questions about this document concisely.")
let response = try await session.respond(to: "Document:\n\(docText)\n\nQuestion: \(userQuestion)")
```

**Structured output for summaries:**
```swift
@Generable
struct DocSummary {
    @Guide(description: "One paragraph summary")
    let summary: String

    @Guide(description: "Key points, max 5")
    let keyPoints: [String]
}

let result = try await session.respond(to: docText, generating: DocSummary.self)
```

**Privacy:** All processing on-device. No network. No API keys. No data leaves the Mac.

**Limitations to communicate to user:**
- Works best for summarization, extraction, simple Q&A
- Not for complex reasoning or math
- Large documents truncated to fit context window

---

## Layout

Three-column NavigationSplitView (Xcode-style):

```
┌─────────────┬──────────────────────┬─────────────┐
│             │                      │             │
│  File List  │   Markdown Viewer    │  AI Chat    │
│  (from      │   (read-only)        │  (about     │
│  package)   │                      │  this doc)  │
│             │                      │             │
└─────────────┴──────────────────────┴─────────────┘
```

- Left: Files in naturalized folder
- Center: Current document rendered
- Right: Chat panel (collapsible)

All panels float, slide, animate with native SwiftUI springs.

---

## Aesthetic

**Liquid Glass (iOS 26 / macOS 26 design language):**
- Material blur backgrounds
- Gradient highlights for depth
- Spring animations on all interactions
- Floating panels with subtle shadows
- Native system colors and fonts

**Refresh Pill:**
- Slack-style floating notification
- Appears when file changes detected
- Liquid glass material
- Tap to reload, or dismiss
- Animates in from bottom, slides out on action

---

## Explicit Non-Goals (The "No" List)

- **No editing** - Read only. Always.
- **No tabs** - One document at a time per window
- **No window state persistence** - Scroll position, chat history reset on close
- ~~No recent files~~ - **Stream feature added** (recent files as sidebar tab)
- **No search across documents**
- **No annotations or highlights**
- **No export/print**
- **No themes beyond system light/dark**
- **No settings panel** - Make good defaults
- **No version history**
- **No cloud sync**
- **No collaboration**

---

## Technical Constraints

| Constraint | Value |
|------------|-------|
| Platform | macOS 26 (Tahoe) - current OS |
| Swift | 5.9+ (for @Observable macro) |
| Architecture | Apple Silicon only (M1+) |
| Sandbox | Disabled (needs file system access) |
| Dependencies | Zero external (Apple frameworks only) |
| Frameworks | SwiftUI, Observation, FoundationModels, UniformTypeIdentifiers, CoreServices |

**Why macOS 26+:** Required for Apple Foundation Models (on-device AI). No fallback - this is a feature, not a limitation. Users who want privacy and on-device AI are on current OS.

---

## Architecture Requirements

| Requirement | Pattern |
|-------------|---------|
| State management | `@MainActor @Observable` classes |
| View bindings | `@Bindable` for all observable objects in views |
| File I/O | Actor or `Task.detached`, never on main thread |
| State updates | Always on MainActor |
| Data models | Value types (structs) |
| Errors | Explicit error types, no force unwraps |
| AI availability | Always check `SystemLanguageModel.default.availability` before AI features |
| Structured output | Use `@Generable` macro for typed AI responses |

---

## File Watching

| Component | Technology |
|-----------|------------|
| Folder monitoring | DispatchSource (single folder) or FSEvents (deep trees) |
| Change detection | Compare modification dates or content hash |
| UI notification | Refresh pill with accept/dismiss |
| Debounce | 0.5s to coalesce rapid changes |

---

## Success Criteria

v1.0 ships when:

1. [ ] Can naturalize a folder into .pixleyreader package
2. [ ] DocumentGroup browser shows packages beautifully
3. [ ] Opening package shows live folder contents
4. [ ] Selecting .md file renders with syntax highlighting
5. [ ] File changes trigger refresh pill
6. [ ] Refresh pill reloads content smoothly
7. [ ] AI chat panel sends document to Foundation Models, shows response
8. [ ] Three-column layout with liquid glass aesthetic
9. [ ] All animations feel native and smooth
10. [ ] No crashes, no data loss, no surprises

---

## Future (v1.1+)

- Pretty diff visualization (lift incoming/outgoing)
- Scroll position locking during refresh
- **Context hot potato** - Two-pass AI for large docs:
  1. Pass headers/outline → model identifies focus areas
  2. Tool calling retrieves specific sections → focused reasoning
- Multiple file context for AI chat
- Keyboard shortcuts
- Touch Bar support

---

## What We're Preserving

From the failed first attempt:
- `MarkdownHighlighter.swift` - Regex-based syntax highlighting (works)
- `MarkdownEditor.swift` - NSViewRepresentable wrapper (works)

Everything else: rebuild from scratch following this BRD.

---

*Ship it right this time.*
