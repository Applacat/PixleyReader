# Pixley Reader v1.0 - Technical Specification

**Version:** 1.0.1
**Date:** 2026-02-01
**Status:** APPROVED (Updated post-QA)

---

## Overview

Pixley Reader is a native macOS companion app for developers working with AI tools. It monitors markdown files, provides beautiful read-only viewing with live refresh, and offers on-device AI chat about document contents.

**Tagline:** Watch what AI writes, ask questions about it, stay in flow.

---

## Navigation Model (UPDATED)

### Single-Window Unified Navigation

The sidebar uses a drill-in/drill-out navigation model with a single hierarchy:

```
ROOT: All Projects (sorted by creation date)
├── Project A (12)          ← total .md files in project
│   ├── docs (8)            ← .md count in subtree
│   │   ├── specs (5)
│   │   └── guides (3)
│   └── notes (4)
├── Project B (3)
└── Project C (0)           ← empty project
```

**Navigation behavior:**
- Click project → drill into project's folder contents
- Click folder → drill into subfolder
- Back button → return to parent level
- Back button at project root → return to Projects list
- Back button fades/disappears at true root (Projects list)

**Folder counts:**
- Display format: `Folder Name (n)` where n = total .md files in subtree
- Helps users see where content lives without drilling blindly

### Launch Behavior

1. **First run:** Open with welcome content in Stream
2. **Subsequent runs:** Restore last navigation position (project + folder depth)
3. **Fallback:** If no saved state, show Projects list root

### Window Model

- **Single window** per instance (no DocumentGroup browser)
- Opening a .pixleyreader file opens in same navigation hierarchy
- Multiple windows only if user explicitly requests (Cmd+N or File > New Window)

---

## Epic Summary

| Epic | Name | Stories | Status |
|------|------|---------|--------|
| 1 | App Shell | 5 | COMPLETE |
| 2 | Package System | 7 | NEEDS REWORK |
| 3 | File Browser | 5 | PENDING |
| 4 | Stream | 4 | PENDING |
| 5 | Markdown Viewer | 4 | PENDING |
| 6 | File Watching + Welcome Content | 7 | PENDING |
| 7 | AI Chat | 6 | PENDING |
| 8 | Polish | 4 | PENDING |

**Total:** 42 user stories

---

## Epic 1: App Shell

**Goal:** Establish the three-column layout foundation with liquid glass aesthetics.

**Status:** COMPLETE (minor rework needed for navigation model)

### US-1.1: Project Setup
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] Package.swift targets macOS 26, Swift 5.9+
- [x] XcodeGen project.yml generates valid .xcodeproj
- [x] `swift build` succeeds with zero warnings
- [x] App launches and shows empty window
- [x] MarkdownHighlighter.swift preserved and compiling
- [x] MarkdownEditor.swift preserved and compiling

---

### US-1.2: Three-Column Layout (UPDATED)
**As a** user
**I want** a three-column layout
**So that** I can see files, content, and chat simultaneously

**Acceptance Criteria:**
- [x] NavigationSplitView with sidebar + content columns
- [x] Inspector panel for AI Chat (right side)
- [x] Columns resize with drag handles
- [x] Minimum widths enforced (sidebar: 200pt, content: 400pt, inspector: 250pt)
- [ ] **NEW:** Sidebar shows unified project/folder navigation (not separate Browser/Stream tabs at top)

**Status:** PARTIAL - needs navigation model update

---

### US-1.3: Liquid Glass Materials
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] Sidebar uses system sidebar styling
- [x] Content area uses subtle background blur (.ultraThinMaterial)
- [x] Inspector panel matches sidebar styling
- [x] Dark mode only (forced via preferredColorScheme)

---

### US-1.4: Empty State Views
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] Sidebar empty state shows appropriate message
- [x] Content empty state: "Select a file to view"
- [x] Inspector empty state: (hidden when collapsed)
- [x] All empty states use SF Symbols and muted colors

---

### US-1.5: Sidebar Navigation (UPDATED - was Segmented Control)
**As a** user
**I want** unified project/folder navigation
**So that** I can browse all my projects and their contents seamlessly

**Acceptance Criteria:**
- [ ] **NEW:** Projects list at root showing all .pixleyreader packages
- [ ] **NEW:** Drill-in navigation to project folders
- [ ] **NEW:** Back button for navigation (fades at root)
- [ ] **NEW:** Folder counts showing .md file totals inline: `Folder Name (12)`
- [ ] **REMOVED:** Browser/Stream segmented control (Stream becomes separate tab or section)
- [ ] Smooth crossfade animations between navigation levels

**Status:** NEEDS REWORK

---

## Epic 2: Package System (Naturalization)

**Goal:** Enable folders to become persistent .pixleyreader packages with live links.

**Status:** COMPLETE (implementation done, needs integration with new navigation model)

### US-2.1: PixleyPackage Document Type
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] .pixleyreader UTI registered in Info.plist
- [x] Package contains Contents/reference.bookmark (security-scoped)
- [x] Package contains Contents/Info.plist (metadata)
- [x] FileDocument conformance implemented
- [ ] Package icon configured

---

### US-2.2: Naturalization Service
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] NaturalizationService.naturalize(folder:) creates package
- [x] Package stored in ~/Library/Application Support/PixleyReader/Packages/
- [x] Default name = folder name
- [x] Duplicate names handled with suffix (-1, -2, etc.)
- [x] Security-scoped bookmark created for original folder

---

### US-2.3: App Launch Integration (UPDATED - was DocumentGroup)
**As a** user
**I want** the app to launch into a useful state
**So that** I can start working immediately

**Acceptance Criteria:**
- [ ] **NEW:** First launch shows welcome content in Stream
- [ ] **NEW:** Subsequent launches restore last navigation state
- [ ] **NEW:** No DocumentGroup browser on launch
- [ ] **NEW:** Projects list shows all packages sorted by creation date
- [ ] **REMOVED:** DocumentGroup scene for .pixleyreader (use URL handler instead)

**Status:** NEEDS REWORK

---

### US-2.4: Dock Drop Handling
**Status:** COMPLETE (implementation exists)

**Acceptance Criteria:**
- [x] Info.plist declares folder drop capability
- [x] onOpenURL handles folder URLs
- [x] Dropped folder triggers naturalization
- [ ] **UPDATED:** Opens in unified navigation (not separate window)

---

### US-2.5: File → Open Folder
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] File → Open Folder shows NSOpenPanel
- [x] Panel allows folder selection (canChooseDirectories = true)
- [x] Selected folder triggers naturalization
- [ ] **UPDATED:** Opens in unified navigation (not separate window)

---

### US-2.6: Security-Scoped Bookmark Lifecycle
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] Call `startAccessingSecurityScopedResource()` when package opens
- [x] Call `stopAccessingSecurityScopedResource()` when package closes
- [x] Track access state to prevent double-start/double-stop
- [x] Handle access failure gracefully (show error, don't crash)

---

### US-2.7: Stale Bookmark Recovery
**Status:** COMPLETE

**Acceptance Criteria:**
- [x] Stale bookmark detected on package open
- [x] Alert shown: "Folder moved or deleted. Locate folder?"
- [x] "Locate" opens NSOpenPanel for folder selection
- [x] Bookmark updated with new location
- [x] "Remove Project" option deletes package

---

## Epic 3: File Browser (Left Column)

**Goal:** Display and navigate files within the unified project hierarchy.

**Status:** PENDING (updated for new navigation model)

### US-3.1: Projects List View (NEW)
**As a** user
**I want** to see all my projects at the root level
**So that** I can choose which project to work in

**Acceptance Criteria:**
- [ ] List all .pixleyreader packages from ~/Library/Application Support/PixleyReader/Packages/
- [ ] Sort by creation date (newest first)
- [ ] Display project name with total .md count: `Project Name (12)`
- [ ] Fat chunky cells for easy clicking
- [ ] Click to drill into project folder contents

**Tests:**
- Unit: Package enumeration returns correct items
- UI: List displays with proper styling and counts

---

### US-3.2: Folder Contents Display (UPDATED)
**As a** user
**I want** to see files in my project folder
**So that** I can select one to view

**Acceptance Criteria:**
- [ ] Files listed from resolved bookmark URL
- [ ] .md files shown with full opacity and doc icon
- [ ] Other files shown with reduced opacity (0.5)
- [ ] Files sorted alphabetically
- [ ] Folders shown first with .md count: `subfolder (5)`
- [ ] **NEW:** Inline count format for folders

**Tests:**
- Unit: File enumeration returns correct items
- Unit: .md counting works recursively
- UI: List displays with proper styling

---

### US-3.3: File Selection
**Status:** PENDING

**Acceptance Criteria:**
- [ ] Single click selects file
- [ ] Selection highlights row
- [ ] Selection triggers content load in center column
- [ ] Non-.md files are not selectable (or show "Not a markdown file")

---

### US-3.4: Drill-In/Out Navigation (UPDATED - was Subfolder Navigation)
**As a** user
**I want** to navigate through folder hierarchy with back button
**So that** I can access nested files and return easily

**Acceptance Criteria:**
- [ ] Folders clickable to drill into
- [ ] **NEW:** Back button in header (chevron left)
- [ ] **NEW:** Back button fades/disappears at true root (Projects list)
- [ ] **NEW:** Current location shown in header (folder name or "Projects")
- [ ] Smooth crossfade animation between levels

**Tests:**
- UI: Folder navigation works
- UI: Back button returns to parent
- UI: Back button hidden at root

---

### US-3.5: File Browser Tests
**As a** developer
**I want** comprehensive tests
**So that** the browser is reliable

**Acceptance Criteria:**
- [ ] Unit tests for FileSystemService
- [ ] Unit tests for file filtering logic
- [ ] Unit tests for .md counting
- [ ] UI tests for selection behavior
- [ ] UI tests for navigation

---

## Epic 4: Stream (Left Column - Separate Section)

**Goal:** Provide chronological access to recently opened files.

**Note:** Stream is now a separate section/mode, not a tab. Consider making it accessible via a toolbar button or keyboard shortcut.

### US-4.1: RecentFilesManager
**Status:** PENDING

**Acceptance Criteria:**
- [ ] @MainActor @Observable class
- [ ] Stores file URLs with timestamps
- [ ] Unlimited history (no cap)
- [ ] Persists to SQLite database (not UserDefaults - scales better)
- [ ] Database location: ~/Library/Application Support/PixleyReader/stream.db
- [ ] Loads on app launch

---

### US-4.2: Stream List View
**Status:** PENDING

**Acceptance Criteria:**
- [ ] List shows file name and relative timestamp ("2 min ago")
- [ ] Tap opens file in viewer
- [ ] Files from packages show package name as subtitle
- [ ] Single files show path as subtitle

---

### US-4.3: Stream Management
**Status:** PENDING

**Acceptance Criteria:**
- [ ] Swipe to delete single item
- [ ] "Clear All" button in stream header
- [ ] Confirmation before Clear All
- [ ] Deletion updates immediately

---

### US-4.4: Stream Tests
**Status:** PENDING

**Acceptance Criteria:**
- [ ] Unit tests for RecentFilesManager
- [ ] Unit tests for persistence
- [ ] UI tests for list interactions

---

## Epic 5: Markdown Viewer (Center Column)

**Goal:** Render markdown beautifully with syntax highlighting.

### US-5.1: MarkdownHighlighter Integration
**Status:** PENDING

**Acceptance Criteria:**
- [ ] MarkdownHighlighter.swift integrated
- [ ] Patterns compile once at init
- [ ] Theme uses system colors
- [ ] Headers, code, bold, italic, links, lists, blockquotes, tables styled

---

### US-5.2: MarkdownEditor Read-Only Mode
**Status:** PENDING

**Acceptance Criteria:**
- [ ] MarkdownEditor.swift integrated
- [ ] isEditable = false on NSTextView
- [ ] Cursor is arrow, not I-beam
- [ ] No typing, pasting, or editing possible
- [ ] Scrolling works smoothly

---

### US-5.3: Document Loading
**Status:** PENDING

**Acceptance Criteria:**
- [ ] File loaded via async Task.detached
- [ ] Loading indicator shown during load
- [ ] Content displayed with highlighting
- [ ] Error shown if file unreadable

---

### US-5.4: Single File Support
**Status:** PENDING

**Acceptance Criteria:**
- [ ] .md file drop/open bypasses naturalization
- [ ] Opens in same three-column layout (consistency)
- [ ] File added to Stream history
- [ ] File watching works for single files

---

## Epic 6: File Watching + Welcome Content

**Goal:** Detect file changes and enable smooth refresh.

### US-6.1: Folder-Based File Monitor
**Status:** PENDING

**Acceptance Criteria:**
- [ ] FolderWatcher class using FSEvents (not DispatchSource on file)
- [ ] Watches parent folder of currently open file
- [ ] Ignores temp files (*.tmp, .*, ~*)
- [ ] Fires onChange when target file modified, renamed, or replaced
- [ ] Handles vim/sed/AI tool pattern: create temp → delete original → rename temp
- [ ] Properly stops watching on cleanup

---

### US-6.2: Change Debouncing
**Status:** PENDING

**Acceptance Criteria:**
- [ ] 0.5 second debounce window
- [ ] Multiple changes within window coalesce
- [ ] Single notification after debounce

---

### US-6.3: Refresh Pill UI
**Status:** PENDING

**Acceptance Criteria:**
- [ ] Pill floats above content (bottom center)
- [ ] Liquid glass material
- [ ] Text: "Content updated"
- [ ] Reload button (primary action)
- [ ] Dismiss button (X or swipe)
- [ ] Spring animation on appear/disappear

---

### US-6.4: Reload Action
**Status:** PENDING

**Acceptance Criteria:**
- [ ] Tap Reload reloads file content
- [ ] Highlighting reapplied
- [ ] Scroll position maintained if possible
- [ ] Pill dismisses after reload
- [ ] Cmd+R keyboard shortcut triggers reload

---

### US-6.5: Pill Persistence
**Status:** PENDING

**Acceptance Criteria:**
- [ ] Pill stays visible until Reload or Dismiss
- [ ] No auto-dismiss timeout
- [ ] Multiple file changes don't stack pills (single pill, "Content updated")

---

### US-6.6: Bundled Welcome Content
**Status:** PENDING

**Acceptance Criteria:**
- [ ] App bundle contains Resources/Welcome/ folder with markdown files
- [ ] On first launch (no Stream history), copy welcome files to temp location
- [ ] Welcome files auto-added to Stream in order:
  1. "Welcome to Pixley Reader.md" (overview)
  2. "Getting Started.md" (opening folders, browsing)
  3. "Using the Stream.md" (recent files, clear history)
- [ ] First welcome file auto-selected and displayed in viewer
- [ ] User can delete welcome files from Stream like any other file
- [ ] Welcome files only appear once (flag stored in UserDefaults)

---

### US-6.7: Welcome Content Writing
**Status:** PENDING

**Acceptance Criteria:**
- [ ] Welcome files use all markdown features (headings, lists, code, links)
- [ ] Content explains the unified navigation model
- [ ] Content explains Stream
- [ ] Content mentions AI Chat (coming soon until Epic 7)
- [ ] Tone is friendly, concise, developer-focused
- [ ] Each file < 500 words

---

## Epic 7: AI Chat (Right Column)

**Goal:** Enable on-device AI conversations about document content.

(Stories US-7.1 through US-7.6 unchanged)

---

## Epic 8: Polish

**Goal:** Ensure the app feels delightful and native.

(Stories US-8.1 through US-8.4 unchanged)

---

## Technical Requirements

### Architecture Patterns
- All observable state: `@MainActor @Observable`
- View bindings: `@Bindable` for observable objects
- File I/O: `Task.detached` or actor
- Data models: Value types (structs)
- Errors: Explicit error types
- **NEW:** Single-window architecture with unified navigation state

### Dependencies
- SwiftUI
- Observation
- FoundationModels
- UniformTypeIdentifiers
- CoreServices

### Platform
- macOS 26 (Tahoe)
- Apple Silicon only (M1+)
- No sandbox
- **Dark mode only**

---

## Out of Scope (v1.0)

- Editing
- Tabs
- Search across documents
- Annotations
- Export/print
- Light mode (dark only for v1.0)
- Settings panel
- Version history
- Cloud sync
- Collaboration
- Onboarding flow (use welcome content instead)
- Pretty diff visualization
- Context hot potato for AI
- **Save Stream as Project** (v1.1 feature)

---

## v1.1 Roadmap

- Save Stream as Project (group recent files into a new project)
- Light mode option
- Window state persistence
- Search across documents

---

## Success Criteria

v1.0 ships when all 42 user stories pass acceptance criteria and test coverage exceeds 80%.
