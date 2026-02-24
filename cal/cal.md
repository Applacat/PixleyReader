# Cal Journal

**Project:** Pixley Reader
**Created:** 2026-02-01
**Stack:** Swift 6.2, SwiftUI, macOS 26 (Tahoe)

---

## 2026-02-02 - Documentation Reset

**Problem:** cal.md and other docs were out of sync with reality. Referenced features that don't exist (Stream, Projects, SQLite), wrong Swift version (5.9 instead of 6.2).

**Actions taken:**
- Created INDEX.md as source-of-truth tracker
- Archived 5 stale docs to docs/archive/
- Fixed CLAUDE.md (Swift 6.0 → 6.2, updated file list)
- Rewrote this file from scratch

**Current reality:**
- v1 is functional (start screen, folder browser, markdown viewer, AI chat)
- v1.1 in progress (3 stories, 2 phases)
- Story 1 complete (drill-down bug fixed)
- No Stream feature, no SQLite, no Projects concept

---

## 2026-02-02 - Story 1 Complete

**Fix:** Replaced NavigationSplitView with HStack for browser layout.

**Root cause:** NavigationSplitView + NavigationStack hybrid pattern doesn't work properly. NavigationStack needs to be independent.

**Architecture now:**
```
HStack(spacing: 0)
├── NavigationStack (handles drill-down)
│   └── FolderListView → pushes → FolderListView
├── Divider
└── Detail view (observes selectedFile)
```

---

## Design Principles (Emerging)

1. **Apple Happy Path** - Use native patterns, don't fight the framework
2. **iOS Files App as model** - Sidebar should feel like iOS Files
3. **Liquid Glass aesthetic** - Visual warmth, not clinical
4. **No persistence** - Open folder each session (simplicity)

---

## Known Issues

- ~~Sidebar styling not native~~ **FIXED 2026-02-02**
- ~~Click targets too small~~ **FIXED 2026-02-02**
- Need iOS 26 / macOS 26 pattern documentation
- Need Liquid Glass design documentation

---

## 2026-02-02 - Native UI Refactor

**Problem:** Sidebar and StartView had custom spaghetti code with tiny click targets. User wanted Pixelmator-style generous buttons.

**Changes made:**

### Sidebar (FileBrowserSidebar)
- Removed `List(children:)` with tiny disclosure triangles
- New `FileRowView` with manual expand state via `expandedFolders: Set<String>`
- **Tap folder row → expand/collapse** (not just triangle)
- **Tap markdown file → select it**
- Generous padding: 10pt vertical, 8pt horizontal
- Hover states on all rows via `SidebarRowStyle`
- Animated chevron rotation

### StartView (Pixelmator-style)
- New `FolderShortcutButton` with `FolderButtonStyle` (hover + press states)
- New `RecentFolderButton` with hover-to-reveal remove button
- Full-width clickable areas via `.contentShape(Rectangle())`
- Ask Pixley section preserved with file attachment
- Native `.textFieldStyle(.roundedBorder)` instead of custom
- Native `.buttonStyle(.borderless)` instead of `.plain`

### ChatView
- Input area: `.textFieldStyle(.roundedBorder)`
- Buttons: `.buttonStyle(.borderless)` with proper hit targets
- Clear button now uses label: "Clear" with icon

### BrowserView
- Separated toolbar items (AI Chat toggle + Close Folder)
- AI Chat toggle in `.primaryAction`, Close in `.secondaryAction`

**Principle confirmed:** "Apple Happy Path" - use native SwiftUI patterns, generous padding, proper button styles.

---

## 2026-02-02 - Context & Performance Session

### AI Chat Improvements

**Problem 1:** Chat froze on large documents (context overflow)
- **Fix:** Truncate docs to 8K chars max
- Added truncation warning banner

**Problem 2:** Chat had no memory - every message re-sent full document
- **Fix:** Added conversation history support
  - First question: full doc context (8K max)
  - Follow-ups: last 6 messages + brief doc excerpt (2K)
  - System prompt tells AI to use conversation history

**Problem 3:** User couldn't see context usage
- **Fix:** Added "Memory" meter in chat header
  - Brain icon + gauge bar + percentage
  - Green → orange (70%) → red (90%)
  - Shows mode: "Full doc", "Truncated", or "Chat"
  - "Forget" button (ESC shortcut) to clear and reset

### Sidebar Improvements

**Problem:** Markdown counts were wrong (didn't add up)
- **Fix:** Proper OOD - children count bubbles up to parents
  - Files: 1 if .md, 0 otherwise
  - Folders: sum of children's markdownCount
- Removed old slow `countMarkdownFilesSync()` (dead code)

**Problem:** Names truncated with "..." - couldn't read them
- **Fix:**
  - Removed `.lineLimit(1)`
  - Added `.fixedSize(horizontal: true, vertical: false)`
  - Wrapped in horizontal ScrollView
  - Full-width clickable rows

### Folder Caching

**New feature:** Cache folder trees for faster loading
- Store tree with modification dates in Application Support
- On reload, only rescan changed folders
- `loadTreeWithDiff()` for smart incremental updates

### Ask Pixley Improvements

**New feature:** "Ask" pill on recent folders
- Hover recent folder → shows "Ask" pill
- Click "Ask" → loads folder as context for Ask Pixley
- Scans folder, shows markdown files + structure
- Placeholder: "Ask about this folder..."

### Backlog Added

- **Welcome Tour Folder** (v1.2+): Bundled markdown files explaining features, click Pixley mascot to open

---

## 2026-02-02 - Recents Feature

**Request:** Rename "Recent Folders" to "Recents" and show last 4 clicked files.

**Changes made:**

### RecentFoldersManager.swift
- `RecentItem` struct already existed (for unified model)
- Added `removeFolderByPath()` for path-based removal
- Updated `removeRecentFile()` to match by path (not ID)
- `getAllRecents()` combines folders + files sorted by date

### ContentView.swift
- Added `addRecentFile()` call in `handleTap()` when markdown selected
- Tracks parent folder for security scope resolution

### StartView.swift
- Changed `recentFolders: [RecentFolder]` → `recentItems: [RecentItem]`
- Header: "Recent Folders" → "Recents"
- New `RecentItemButton` shows folder icon or doc icon based on `isFolder`
- New methods: `openRecentItem()`, `askAboutItem()`, `removeRecentItem()`
- Files show parent folder name as subtitle
- List height 200 → 260 for more items

**Result:** Start screen now shows combined view of up to 10 folders + 4 most recently clicked files, sorted by date, with appropriate icons and hover actions.

---

## 2026-02-02 - Welcome Folder & App Icon

### Welcome Tour Implemented

Created `Resources/Welcome/` with 6 markdown files for first-time users:
- `01-Welcome.md` - What is Pixley Reader, what's markdown
- `02-Browsing-Folders.md` - How to browse and navigate
- `03-Ask-Pixley.md` - Using Ask Pixley on start screen
- `04-AI-Chat.md` - Chatting about documents, memory meter
- `05-Keyboard-Shortcuts.md` - ESC to forget, etc.
- `06-Tips-and-Tricks.md` - Drag/drop, privacy, troubleshooting

**Click Pixley mascot** on start screen → opens Welcome folder as guided tour.

Implementation:
- Bundle via `.copy("Resources/Welcome")` in Package.swift
- `PixleyMascotButtonStyle` - scale animation on hover/press
- Copies bundle to temp folder (for security scope access)

### App Icon Added

Created complete macOS icon set from user's 1024x1024 export:
- 10 sizes: 16, 32, 128, 256, 512 @1x and @2x
- Using "Default" variant from Icon Composer export
- Contents.json updated with filenames

### Known Bugs Fixed

- **Bug A** (Quick Open hit targets): Already fixed with `.contentShape(Rectangle())` + generous padding
- **Bug B** (Drill-down in detail pane): Already fixed with tap-to-expand inline (`expandedFolders: Set<String>`)

---

## 2026-02-03 DECISION - App Rename Required

**Issue:** "Pixley" name has potential copyright concerns.

**What stays:** Pixley the mascot character (the image/icon)
**What changes:** App name "Pixley Reader" needs renaming

**Pending:** New name selection

---

## 2026-02-03 AHA - Audit Completion

All Swift 6 concurrency and memory audits pass with 0 issues.

**Fixes applied (previous session):**
- `DispatchQueue.main.asyncAfter` → `Task.sleep` (MarkdownHighlighter)
- Task.detached with @MainActor self → `nonisolated static` methods (FolderService)
- Security-scoped resource double-start → centralized in `AppState.setRootFolder()` only
- Synchronous file I/O → wrapped in `Task.detached` (MarkdownView)
- Removed unused `cacheQueue` DispatchQueue

**Result:** Swift 6 strict concurrency ready, production-ready

---

## 2026-02-05 - Phase 2 Foundation Complete

### Audit Fixes Applied (13 issues)
- Fixed AppState crash from ColorSchemePreferenceModifier
- Removed invalid `[weak self]` on structs (StartView, AIMDReaderApp are value types)
- Made FolderService cache loading async (non-blocking init)
- Added static placeholder in OutlineFileList (avoid allocations in hot path)
- Simplified ChatView async coordination (avoid Swift 6 isolation checker bug)

### Phase 2 Components Created (not yet wired)
- **aimdRenderer package** - MarkdownTheme protocol, SwiftUITheme, 10 syntax themes
- **AppCoordinator** - Decomposed state: NavigationState, UIState, DocumentState
- **SettingsRepository** - Protocol + UserDefaults implementation

### Build Status
✅ Project builds successfully

### Next Task
Wire Phase 2 components into views OR skip to user-visible feature (Phase 4/5)

---

## 2026-02-24 DECISION — v2.0 Submitted to App Store

**Milestone:** Pixley Markdown Reader 2.0 submitted for review.

**App Store changes:**
- **Name:** Pixley Markdown Reader (display name: "Markdown Reader")
- **Subtitle:** "AI Chat & Color Themes" (was "Browse & AI Chat Markdown")
- **Category:** Productivity (primary) + Developer Tools (secondary)
- **Spanish (Mexico) localization** added for US keyword expansion (~doubles indexed keywords)
- **Description** rewritten for prosumer audience (vibe coders, not traditional devs)
- **Promotional text:** "Read what AI writes." tagline lives here now

**ASO strategy:**
- Technical jargon in keyword fields (invisible), plain language in user-facing copy
- No trademarked names (ChatGPT, Claude, Cursor, Copilot) — Apple rejects these
- Screenshot captions indexed as of June 2025 — captions designed for both conversion and search
- Target: 5 ratings to show stars (SKStoreReviewController planned for 2.1)

**Code changes in this session:**
- CFBundleDisplayName: "Pixley Reader" → "Markdown Reader" (Info.plist)
- CURRENT_PROJECT_VERSION: 1 → 3 (all build configs)
- MARKETING_VERSION: 2 (all build configs)
- Folder sort: files before folders (was folders first)
- Welcome files: moved 04/05 into "Tips and Tricks" subfolder
- Welcome content: tables replaced with lists (renderer doesn't support tables)
- Welcome content: rewritten with code blocks, blockquotes, richer markdown
- Theme picker: fixed bug showing "Light + Dark" / "Dark only" instead of theme names
- Settings picker: HStack with custom views → plain Text (menu-style Picker compatibility)

**Key learnings:**
- App Store description is NOT indexed for search — only title, subtitle, keyword field
- Promotional text is NOT indexed — can be updated without new version
- Spanish (Mexico) keywords are indexed in US App Store (cross-localization hack)
- Cross-locale keywords do NOT combine into phrases across locales
- Menu-style SwiftUI Pickers cannot render custom HStack views — use plain Text

**Next for 2.1:**
- SKStoreReviewController implementation (plan ready, 1 service + 2 call sites)
- Screenshots (plan in App Store/screenshots.md)
- Table rendering support (not trivial — needs NSTextTable or WKWebView)

---
