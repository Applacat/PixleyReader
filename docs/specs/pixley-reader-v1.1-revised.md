# Pixley Reader v1.1 - Specification

**Date:** 2026-02-02
**Status:** IN PROGRESS

---

## Product

A sandboxed macOS markdown reader. Open a folder, browse files, view with syntax highlighting, ask AI about content. Dark mode only.

**Tagline:** Watch what AI writes, ask questions about it, stay in flow.

---

## v1.0 Scope - COMPLETE

1. **Start Screen** - Pixley mascot, quick actions, Ask Pixley, recent folders
2. **Browser Window** - Three-column layout, drill-in navigation, markdown counts
3. **Markdown Viewer** - Syntax highlighting, reload pill
4. **AI Chat** - Foundation Models, chat about current document
5. **Ask Pixley** - Natural language input, file attachment, intent parsing

---

## v1.1 Scope

### Execution Order

```
PHASE 1 - Fix + Foundation:
  Story 1: Fix Drill-Down Bug
  Story 2: State Architecture + DI

PHASE 2 - Native UI:
  Story 3: Native Sidebar + Cross-Platform
```

---

### Story 1: Fix Drill-Down Bug

**Priority:** CRITICAL

**Problem:** Drilling into subfolders shows empty content. Security-scoped resource access not maintained.

**Scope:**
- Fix `.navigationDestination` placement (was inside conditional, should be on NavigationStack)
- Ensure `startAccessingSecurityScopedResource()` is called and return value checked
- Log errors if security scope fails

**Acceptance Criteria:**
- [ ] Drilling into any folder shows its contents
- [ ] Works 3+ levels deep
- [ ] Console shows meaningful error if security scope fails

**Verification:** Open Documents → drill into subfolder → drill 3+ levels → content shows

---

### Story 2: State Architecture + Dependency Injection

**Priority:** HIGH

**Problem:** AppState is a god object. Services use singleton pattern. Untestable.

**Scope:**

Split AppState into focused objects:
```swift
@Observable class NavigationState { path, selectedFile }
@Observable class DocumentState { content, needsReload }
@Observable class ChatState { isVisible, initialQuestion }
@Observable class FolderState { rootURL }
```

Make services injectable:
```swift
protocol FolderServiceProtocol { ... }
protocol RecentFoldersProtocol { ... }
```

**Acceptance Criteria:**
- [ ] AppState split into 4 focused observable objects
- [ ] Each state available via @Environment
- [ ] FolderService injectable (not .shared singleton)
- [ ] RecentFoldersManager injectable (not .shared singleton)
- [ ] All existing functionality unchanged

**Opportunistic cleanup during this story:**
- Remove print() statements (touching all files anyway)
- Fix Task.sleep race condition in ChatView
- Remove dead code (NavigationItem enum, PixleyResponse struct)
- Fix redundant `= nil` initializations

**Verification:** Build succeeds, app launches, all features work

---

### Story 3: Native Sidebar + Cross-Platform

**Priority:** HIGH

**Problem:** Custom row views fight the framework. NSOpenPanel is macOS-only. Not iOS portable.

**Scope:**

Native sidebar (iOS Files app style):
```swift
List(selection: $selectedFile) {
    ForEach(items) { item in
        if item.isFolder {
            NavigationLink(value: item.url) {
                Label(item.name, systemImage: "folder")
                    .badge(item.markdownCount)
            }
        } else {
            Label(item.name, systemImage: "doc.text")
                .tag(item.url)
        }
    }
}
```

Cross-platform file picking:
```swift
.fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { ... }
```

**Acceptance Criteria:**
- [ ] Remove custom FolderRowView, FileRowView
- [ ] Use Label for all rows
- [ ] Folders use NavigationLink(value:)
- [ ] Files use List(selection:) binding
- [ ] .badge() for markdown count
- [ ] Non-markdown files dimmed/disabled
- [ ] Replace NSOpenPanel with .fileImporter()
- [ ] Use .swipeActions for delete (not onHover)
- [ ] Keyboard navigation works
- [ ] VoiceOver announces items correctly
- [ ] Builds for iOS target

**Opportunistic cleanup during this story:**
- Fix .animation(value: true) bug in MarkdownView
- Abstract NSColor usage for cross-platform

**Verification:**
- Sidebar looks/feels like iOS Files app
- `xcodebuild -scheme PixleyReader -destination 'platform=iOS Simulator'` succeeds

---

## Architecture (Post v1.1)

```
StartView (launch)
├── User picks folder → BrowserView
├── User asks Pixley about file → BrowserView + chat
└── Recent folder click → BrowserView

BrowserView
├── Sidebar: Native List (drill-in/out)
├── Content: MarkdownView
└── Inspector: ChatView (macOS only)

State (all via @Environment):
├── NavigationState
├── DocumentState
├── ChatState
└── FolderState

Services (protocol-based, injected):
├── FolderServiceProtocol
└── RecentFoldersProtocol
```

---

---

## Known Bugs (fix in relevant story)

### Bug A: Quick Open buttons hit target too small - ✅ FIXED
**Location:** StartView.swift - FolderButton
**Problem:** Only the text/icon is clickable, not the whole button container
**Fix:** Added `.contentShape(Rectangle())` and generous padding. Uses `FolderButtonStyle` with hover states.

### Bug B: Drill-down shows in detail pane instead of sidebar - ✅ FIXED
**Location:** ContentView.swift - NavigationSplitView + NavigationStack
**Problem:** Clicking a folder shows its contents in the detail pane (right side) instead of pushing a new view in the sidebar (left side). Not iOS Files app behavior.
**Fix:** Implemented tap-to-expand behavior with `expandedFolders: Set<String>`. Folders expand/collapse inline, iOS Files app style.

---

## Backlog (v1.2+)

### Welcome Tour Folder - ✅ IMPLEMENTED
**Priority:** NICE-TO-HAVE

**Description:** Bundle a "Welcome" folder with markdown files explaining all app features. Clicking the Pixley mascot image on the start screen opens this folder as a guided tour.

**Implementation:**
- Created `Resources/Welcome/` folder with 6 markdown files:
  - `01-Welcome.md` - What is Pixley Reader, what's markdown
  - `02-Browsing-Folders.md` - How to browse and navigate
  - `03-Ask-Pixley.md` - Using Ask Pixley on start screen
  - `04-AI-Chat.md` - Chatting about documents, memory meter
  - `05-Keyboard-Shortcuts.md` - ESC to forget, etc.
  - `06-Tips-and-Tricks.md` - Drag/drop, privacy, troubleshooting
- Bundle via `.copy("Resources/Welcome")` in Package.swift
- Pixley mascot is now a button with scale animation on hover/press
- Click copies bundle to temp and opens as root folder

**Acceptance Criteria:**
- [x] Pixley image is clickable (visual feedback on hover)
- [x] Click opens browser with Welcome folder
- [x] Welcome files explain all features clearly
- [x] Files work as demo content for first-time users

---

## Out of Scope (v1.x)

- Editing
- File watching (FSEvents)
- Search across documents
- Light mode
- Window state persistence
- iCloud sync

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Story count | 3 | Each delivers coherent outcome |
| Phase count | 2 | Fix+Foundation, then Native UI |
| Cleanup | Opportunistic | Done while touching files, no separate story |
| Navigation | iOS Files app style | Cross-platform portable |
| File picking | .fileImporter() | Works on iOS |
| State | 4 focused objects | Single responsibility |
| Services | Protocol + injection | Testable |
