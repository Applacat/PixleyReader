# AI.md Reader

A native macOS markdown reader for AI-generated files. Watch what AI writes, ask questions about it, stay in flow.

## Vision

Read markdown files elegantly. Browse folder hierarchies, view with syntax highlighting, ask questions via on-device AI. Liquid glass aesthetic. Dark mode only.

**Not** an editor. **Not** feature-heavy. Simple and focused.

## Stack

- Swift 6.2
- SwiftUI
- macOS 26 (Tahoe) - Apple Silicon only
- Apple Foundation Models (on-device LLM via LanguageModelSession)
- No external dependencies
- SwiftData for file metadata persistence

## Current State

**v1.1 IN PROGRESS** - Native UI refactor underway

### Architecture

NavigationSplitView layout:
1. **FileBrowserSidebar** (sidebar) - Hierarchical tree with tap-to-expand folders
2. **MarkdownView** (detail) - Syntax-highlighted markdown viewer
3. **ChatView** (inspector) - AI chat about current document (via Foundation Models)

### Launch Behavior

1. App opens → Shows StartView (Pixelmator-style) with folder shortcuts + recent folders
2. User opens folder → Shows hierarchical tree, tap folder to expand/collapse
3. User selects .md file → Shows in MarkdownView
4. User toggles AI Chat → ChatView slides in as inspector

### Key Files

**Models:**
- `FolderItem.swift` - File/folder with `children: [FolderItem]?` for hierarchy
- `ChatMessage.swift` - AI chat message model
- `ChatConfiguration.swift` - FM constants (document cap, turn limit, timeout)

**Services:**
- `FolderService.swift` - Loads full folder tree recursively via `loadTree()`
- `RecentFoldersManager.swift` - Recent folders + files tracking with security-scoped bookmarks
- `ChatService.swift` - AI chat using Foundation Models with session management, timeout, auto-reset

**Views:**
- `AIMDReaderApp.swift` - App entry, launch behavior
- `ContentView.swift` - BrowserView with NavigationSplitView, FileBrowserSidebar, FileRowView
- `StartView.swift` - Pixelmator-style welcome with FolderShortcutButton, RecentItemButton (folders + files)
- `MarkdownView.swift` - Markdown viewer with reload pill
- `ChatView.swift` - AI chat with "Thinking..." indicator + full response display

**Resources:**
- `Assets.xcassets` - App assets including AIMD mascot

## Foundation Models Integration

AI chat uses Apple's on-device Foundation Models framework:
- `LanguageModelSession` with instructions containing truncated document (~2500 chars)
- `respond(to:)` for plain text Q&A (no streaming without @Generable)
- Catches all `GenerationError` types: `exceededContextWindowSize`, `guardrailViolation`, `unsupportedLanguageOrLocale`
- 30-second timeout wrapper prevents hangs
- Auto-resets session after 3 Q&A turns to stay within 4096-token context window
- Fresh session per "Forget" reset
- Availability check via `SystemLanguageModel.default.availability`

## Architecture Rules

- All observable state: `@MainActor @Observable`
- View bindings: `@Bindable` for observable objects
- File I/O: `Task.detached` or async/await
- Data models: Value types (structs)
- Errors: Explicit error types, no force unwraps
- Single-window architecture

## Building

**Swift Package Manager:**
```bash
cd PixleyWriter && swift build
```

**Xcode:**
```bash
cd PixleyWriter && xcodegen generate
open AIMDReader.xcodeproj
```

## v1.1 Roadmap

See `docs/specs/aimd-reader-v1.1-revised.md` for current spec.

**Phase 1 - Fix + Foundation:**
- Story 1: Fix Drill-Down Bug [COMPLETE]
- Story 2: State Architecture + DI

**Phase 2 - Native UI:**
- Story 3: Native Sidebar + Cross-Platform (iOS Files app style)

**Out of Scope (v1.x):**
- File watching, search, light mode, editing
