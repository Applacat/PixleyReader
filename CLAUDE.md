# Pixley Markdown Reader

A native macOS markdown reader for AI-generated files. Watch what AI writes, ask questions about it, stay in flow.

## Vision

Read markdown files elegantly. Browse folder hierarchies, view with syntax highlighting, ask questions via on-device AI. Liquid glass aesthetic. System/Light/Dark appearance.

**Not** an editor. **Not** feature-heavy. Simple and focused.

## Stack

- Swift 6.2
- SwiftUI
- macOS 26 (Tahoe) - Apple Silicon only
- Apple Foundation Models (on-device LLM via LanguageModelSession)
- No external dependencies
- SwiftData for file metadata persistence

## Current State

**v1.1 IN PROGRESS** - Story 1 complete, native UI refactor underway

### Architecture

**AppCoordinator** owns all state, decomposed into focused containers:
- `NavigationState` — folder/file selection, security-scoped bookmark lifecycle
- `UIState` — panel visibility, appearance
- `DocumentState` — document content, loading

Views observe state via Environment, mutate through coordinator methods.

**Layout:** NavigationSplitView with:
1. **OutlineFileList** (sidebar) - NSOutlineView-backed hierarchical tree
2. **MarkdownView** (detail) - Syntax-highlighted markdown viewer with file watching
3. **ChatView** (inspector) - AI chat about current document (via Foundation Models)

### Launch Behavior

1. App opens → Shows StartView (Pixelmator-style) with folder shortcuts + recent folders/files
2. User opens folder → Shows hierarchical tree, tap folder to expand/collapse
3. User selects .md file → Shows in MarkdownView, FileWatcher monitors for changes
4. User toggles AI Chat → ChatView slides in as inspector

### Key Files

**Coordinator:**
- `AppCoordinator.swift` - Central state coordinator with NavigationState, UIState, DocumentState

**Models:**
- `FolderItem.swift` - File/folder with `children: [FolderItem]?` for hierarchy
- `ChatMessage.swift` - AI chat message model
- `ChatConfiguration.swift` - FM constants (document cap, turn limit, timeout)
- `AppError.swift` - Explicit error types

**Services:**
- `FolderService.swift` - Loads full folder tree recursively via `loadTree()`, disk cache
- `RecentFoldersManager.swift` - Recent folders + files tracking with security-scoped bookmarks
- `SecurityScopedBookmarkManager.swift` - Bookmark creation, resolution, stale refresh
- `ChatService.swift` - AI chat using Foundation Models with session management, timeout, auto-reset
- `ChatInputValidator.swift` - Input validation before sending to FM
- `FileWatcher.swift` - DispatchSource file monitoring with reload pill
- `WelcomeManager.swift` - First-launch welcome state
- `FolderTreeFilter.swift` - Search/filter within folder tree

**Persistence:**
- `FileMetadata.swift` / `Bookmark.swift` - SwiftData `@Model` classes
- `FileMetadataRepository.swift` - Protocol abstraction for metadata persistence
- `SwiftDataMetadataRepository.swift` - SwiftData implementation with schema versioning

**Settings:**
- `SettingsRepository.swift` - UserDefaults-backed reactive settings (appearance, rendering, behavior)

**Views:**
- `AIMDReaderApp.swift` - App entry, window management, AppDelegate
- `ContentView.swift` - BrowserView with NavigationSplitView
- `StartView.swift` - Pixelmator-style welcome with drag-and-drop
- `MarkdownView.swift` - Markdown viewer with reload pill
- `ChatView.swift` - AI chat with "Thinking..." indicator + full response display
- `SettingsView.swift` - Multi-tab settings (Appearance, Rendering, Behavior)
- `OutlineFileList.swift` - NSOutlineView-backed sidebar (NSViewRepresentable)
- `QuickSwitcher.swift` - Cmd+K file switcher
- `ErrorBanner.swift` - Dismissible error display
- `LineNumberRulerView.swift` - Line number gutter for markdown editor
- `MarkdownEditor.swift` - NSTextView-backed editor (NSViewRepresentable)
- `MarkdownHighlighter.swift` - Regex-based syntax highlighting

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
- Story 2: State Architecture + DI [COMPLETE] — AppCoordinator pattern

**Phase 2 - Native UI:**
- Story 3: Native Sidebar + Cross-Platform (iOS Files app style)

**Out of Scope (v1.x):**
- Search, editing
