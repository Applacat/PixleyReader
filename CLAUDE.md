# Pixley Reader

A native macOS markdown reader for AI-generated files. Watch what AI writes, ask questions about it, stay in flow.

## Vision

Read markdown files elegantly. Browse folder hierarchies, view with syntax highlighting, ask questions via on-device AI. Liquid glass aesthetic. Dark mode only.

**Not** an editor. **Not** feature-heavy. Simple and focused.

## Stack

- Swift 6.2
- SwiftUI
- macOS 26 (Tahoe) - Apple Silicon only
- Apple Foundation Models (on-device AI)
- No external dependencies
- No persistence (open folder each session)

## Current State

**v1.1 IN PROGRESS** - Native UI refactor underway

### Architecture

NavigationSplitView layout:
1. **FileBrowserSidebar** (sidebar) - Hierarchical tree with tap-to-expand folders
2. **MarkdownView** (detail) - Syntax-highlighted markdown viewer
3. **ChatView** (inspector) - On-device AI chat about current document

### Launch Behavior

1. App opens → Shows StartView (Pixelmator-style) with folder shortcuts + recent folders
2. User opens folder → Shows hierarchical tree, tap folder to expand/collapse
3. User selects .md file → Shows in MarkdownView
4. User toggles AI Chat → ChatView slides in as inspector

### Key Files

**Models:**
- `FolderItem.swift` - File/folder with `children: [FolderItem]?` for hierarchy
- `ChatMessage.swift` - AI chat message model
- `PixleyIntent.swift` - Structured AI intent parsing

**Services:**
- `FolderService.swift` - Loads full folder tree recursively via `loadTree()`
- `RecentFoldersManager.swift` - Recent folders tracking with security-scoped bookmarks

**Views:**
- `PixleyReaderApp.swift` - App entry, AppState (simplified, no navigationPath)
- `ContentView.swift` - BrowserView with NavigationSplitView, FileBrowserSidebar, FileRowView
- `StartView.swift` - Pixelmator-style welcome with FolderShortcutButton, RecentFolderButton
- `MarkdownView.swift` - Markdown viewer with reload pill
- `ChatView.swift` - AI chat using Foundation Models
- `AITestView.swift` - Foundation Models testing

**Resources:**
- `Assets.xcassets` - App assets including Pixley mascot

## Apple Foundation Models (2026 API)

```swift
import FoundationModels

// Check availability
guard SystemLanguageModel.default.availability == .available else { return }

// Basic usage
let session = LanguageModelSession(instructions: "Your system prompt")
let response = try await session.respond(to: userPrompt)
```

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
open PixleyReader.xcodeproj
```

## v1.1 Roadmap

See `docs/specs/pixley-reader-v1.1-revised.md` for current spec.

**Phase 1 - Fix + Foundation:**
- Story 1: Fix Drill-Down Bug [COMPLETE]
- Story 2: State Architecture + DI

**Phase 2 - Native UI:**
- Story 3: Native Sidebar + Cross-Platform (iOS Files app style)

**Out of Scope (v1.x):**
- File watching, search, light mode, editing
