# Pixley Reader v1.1 - Specification

**Date:** 2026-02-02
**Status:** IN PROGRESS

---

## Product

A sandboxed macOS markdown reader. Open a folder, browse files, view with syntax highlighting, ask AI about content. Dark mode only.

**Tagline:** Watch what AI writes, ask questions about it, stay in flow.

---

## v1.0 Scope - COMPLETE

### What Was Built

1. **Start Screen** (Pixelmator-style)
   - Left panel: Pixley mascot, app title, quick actions (Home, Documents, Choose Folder)
   - Right panel: Ask Pixley input with file attachment, recent folders list
   - Drag-drop folder support
   - Security-scoped bookmarks for recent folders

2. **Browser Window**
   - Three-column layout: sidebar, content, chat inspector
   - Drill-in/drill-out folder navigation with back button
   - Markdown counts on folders
   - File selection triggers content load

3. **Markdown Viewer**
   - Syntax highlighting via MarkdownHighlighter
   - Read-only NSTextView wrapper
   - Reload pill for file changes (Cmd+R)

4. **AI Chat**
   - Foundation Models integration (on-device)
   - Chat about current document
   - Structured output with @Generable contracts

5. **Ask Pixley (Start Screen)**
   - Natural language input
   - File attachment for context
   - PixleyIntent contract parsing (navigate, summarize, find, answer)

---

## v1.1 Scope - IN PROGRESS

### Story 0: Quick Actions UX Redesign

**Priority:** HIGH

**Reason:** Home folder causes sandbox issues. Reorganize with clearer visual hierarchy.

**Layout:**
```
Quick Open
┌─────────────────┐
│    Documents    │
│    Downloads    │
│     Desktop     │
│ Choose Folder...│
└─────────────────┘
```

**Changes:**
- Remove "Home" button
- Add "Quick Open" section label
- 4 buttons: Documents, Downloads, Desktop, Choose Folder...

**Acceptance Criteria:**
- [x] "Quick Open" label above button group
- [x] 4 buttons in group (Apple pattern)
- [x] All buttons work correctly with NSOpenPanel

---

### Story 1: Ask Pixley Opens Browser with Context

**As a** user
**I want** Ask Pixley to open the browser when I ask about a file
**So that** I can see the document while getting AI assistance

**Current behavior:** Ask Pixley shows a text response in the start screen

**Expected behavior:**
1. User attaches a file and asks a question
2. App opens the browser window
3. File's parent folder becomes the root
4. File is selected in navigation tree
5. Chat panel opens with the conversation context

**Acceptance Criteria:**
- [x] Attached file's parent folder set as root
- [x] File visible and selected in sidebar
- [x] Chat panel opens automatically
- [x] Initial question appears in chat
- [x] AI response continues in chat panel

---

### Story 2: Ask Pixley File Picker Redesign

**As a** user
**I want** a clearer way to attach a file to my question
**So that** the interaction feels native and obvious

**Current behavior:** Separate doc icon button next to text field

**Expected behavior:**
1. Label reads: "Ask Pixley about [Choose File...]"
2. "Choose File..." is a standard macOS button (system style)
3. Clicking opens file picker
4. After selection, button becomes a pill showing filename
5. Clicking the pill opens picker again to replace file
6. Text field below for the actual question

**Acceptance Criteria:**
- [x] "Ask Pixley about" label with inline file picker button
- [x] Standard macOS button style for "Choose File..."
- [x] Selected file shown as pill (rounded, clickable to replace)
- [x] Pill click replaces file (not separate X button)
- [x] Question text field separate from file selection
- [x] Remove old doc icon button

---

### Story 3: Native Sidebar Refactor

**As a** user
**I want** the folder sidebar to feel native
**So that** it behaves like iOS Files app and could drop into an iPhone app unchanged

**Current behavior:** Custom FolderRowView/FileRowView with manual HStack layouts, custom padding, buttonStyle(.plain) - fights the system, feels non-native, drilling into folders shows empty.

**Expected behavior:**
1. Standard SwiftUI List with drill-in NavigationLink
2. Native row styling - let the system handle selection, insets, heights
3. Use `Label` for icon + text
4. Markdown count is just secondary text in the row
5. No custom view wrappers, no button overrides

**Acceptance Criteria:**
- [ ] Remove FolderRowView, FileRowView custom structs
- [ ] Use standard List rows with Label
- [ ] Markdown count shown as secondary/trailing text
- [ ] Feels native - portable to iOS unchanged
- [ ] Drilling into folders shows contents (bug fix)

---

## Architecture

```
StartView (launch)
├── User picks folder → BrowserView
├── User asks Pixley about file → BrowserView with file selected + chat open
└── Recent folder click → BrowserView

BrowserView
├── Sidebar: FolderBrowserView (drill-in/out)
├── Content: MarkdownView
└── Inspector: ChatView (toggle)
```

**Key Files:**
- `PixleyReaderApp.swift` - App entry, window management
- `StartView.swift` - Launch screen with Ask Pixley
- `BrowserView.swift` - Three-column layout
- `PixleyIntent.swift` - AI contract for intent parsing

---

## Out of Scope (v1.x)

- Editing
- File watching (FSEvents)
- Search across documents
- Light mode
- Window state persistence
- iCloud sync
