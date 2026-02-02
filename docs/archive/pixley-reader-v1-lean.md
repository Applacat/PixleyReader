# Pixley Reader v1.0 - Lean Spec

**Date:** 2026-02-02
**Status:** APPROVED
**Estimate:** 2-3 days

---

## Product

A sandboxed macOS markdown reader. Open a folder, browse files, view with syntax highlighting, ask AI about content. Dark mode only.

**Tagline:** Watch what AI writes, ask questions about it, stay in flow.

---

## Architecture

```
Launch
├── Show Welcome content (bundled markdown)
├── User drags folder or File > Open
├── Folder contents appear in sidebar
├── Click file → view in center
├── AI Chat in right panel
└── Quit → done (no persistence needed)
```

**Sandboxed:** Yes (App Store ready)
**Persistence:** None (open folder each session)
**External deps:** None

---

## Target Structure (Wanderlust-style)

```
Sources/
├── PixleyReaderApp.swift
├── Models/
│   ├── FolderItem.swift          → File/folder data structure
│   └── ChatMessage.swift         → AI chat messages
├── Services/
│   ├── FolderService.swift       → Load folder contents, count .md
│   ├── FolderWatcher.swift       → FSEvents file monitoring
│   └── AIService.swift           → Foundation Models wrapper
├── Views/
│   ├── ContentView.swift         → Root 3-column layout
│   ├── Screens/
│   │   ├── WelcomeView.swift     → First-launch welcome
│   │   ├── FolderBrowserView.swift → Sidebar drill-in/out
│   │   ├── MarkdownView.swift    → Center panel viewer
│   │   └── ChatView.swift        → AI chat panel
│   └── Components/
│       ├── FolderRow.swift       → Folder list item
│       ├── FileRow.swift         → File list item
│       ├── ReloadPill.swift      → "Content updated" pill
│       ├── EmptyState.swift      → Empty state component
│       └── BackButton.swift      → Navigation back button
├── Extensions/
│   └── Color+Pixley.swift        → Custom colors (if needed)
├── MarkdownHighlighter.swift     → KEEP (syntax highlighting)
└── MarkdownEditor.swift          → KEEP (NSTextView wrapper)
Resources/
└── Welcome/
    ├── Welcome.md
    ├── Getting Started.md
    └── AI Chat.md
```

---

## Phase 0: Cleanup (Do First)

**Goal:** Remove package system, establish clean structure.

### Delete These Files
```
Sources/Services/NaturalizationService.swift
Sources/Services/PixleyPackage.swift
Sources/Services/PackageDocument.swift
Sources/Services/ProjectsService.swift
Sources/Views/PackageContentView.swift
Sources/Views/ProjectsListView.swift
Sources/Models/NavigationState.swift
```

### Reorganize to Target Structure
```bash
# Create new folders
mkdir -p Sources/Models
mkdir -p Sources/Services
mkdir -p Sources/Views/Screens
mkdir -p Sources/Views/Components
mkdir -p Sources/Extensions
mkdir -p Resources/Welcome

# Move existing files
mv Sources/Views/SidebarView.swift Sources/Views/Screens/FolderBrowserView.swift
mv Sources/Views/ContentPanelView.swift Sources/Views/Screens/MarkdownView.swift
mv Sources/Views/DetailPanelView.swift Sources/Views/Screens/ChatView.swift
mv Sources/Views/FolderContentsView.swift Sources/Views/Components/  # extract components
```

### Simplify PixleyReaderApp.swift
- Remove all NaturalizationService references
- Remove DocumentGroup remnants
- Simple folder opening via NSOpenPanel
- Track open folder URL in AppState (transient, not persisted)

### New AppState (minimal)
```swift
@MainActor @Observable
final class AppState {
    var openFolderURL: URL? = nil        // Currently open folder (transient)
    var selectedFileURL: URL? = nil      // Selected file to view
    var navigationPath: [URL] = []       // Breadcrumb for drill-in/out
    var isAIChatVisible: Bool = false
    var fileHasChanges: Bool = false     // Show reload pill
}
```

---

## Phase 1: Core Reading

**Goal:** Open folder → browse → view markdown

### FolderService.swift
```swift
@MainActor
final class FolderService {
    func loadContents(at url: URL) async throws -> [FolderItem]
    func countMarkdownFiles(in url: URL) async -> Int
}
```

### FolderItem.swift
```swift
struct FolderItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isFolder: Bool
    let isMarkdown: Bool
    var markdownCount: Int  // For folders only
}
```

### FolderBrowserView.swift
- Header with back button (fades at root)
- Current location title
- List of FolderItems
- Folders show count: `docs (12)`
- Click folder → drill in (push to navigationPath)
- Click file → select (set selectedFileURL)

### MarkdownView.swift
- Observe selectedFileURL from AppState
- Load file content async
- Apply MarkdownHighlighter
- Display in MarkdownEditor (read-only)
- Loading/error states

---

## Phase 2: File Watching

**Goal:** Detect changes, offer reload

### FolderWatcher.swift
```swift
@MainActor @Observable
final class FolderWatcher {
    func watch(file: URL)
    func stop()
    var hasChanges: Bool
}
```
- Use FSEvents on parent directory
- 0.5s debounce
- Set `appState.fileHasChanges = true` on change

### ReloadPill.swift
- Floating pill at bottom center
- "Content updated" + Reload button
- Liquid glass material
- Spring animation in/out
- Cmd+R keyboard shortcut

---

## Phase 3: AI Chat

**Goal:** Ask questions about current document

### AIService.swift
```swift
@MainActor @Observable
final class AIService {
    var isAvailable: Bool
    var messages: [ChatMessage] = []

    func ask(_ question: String, context: String) async throws -> String
    func clear()
}
```
- Check `SystemLanguageModel.default.availability`
- Use `LanguageModelSession` with document as context
- Ephemeral (clears on file change)

### ChatMessage.swift
```swift
struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role  // .user or .assistant
    let content: String

    enum Role { case user, assistant }
}
```

### ChatView.swift
- Message list (ScrollView)
- Input field at bottom
- Send button
- Clear button in header
- "AI not available" state

---

## Phase 4: Welcome Content

**Goal:** First-launch experience with bundled content

### Resources/Welcome/
```
Welcome.md          → What is Pixley Reader
Getting Started.md  → How to open folders
AI Chat.md          → Using the AI assistant
```

### WelcomeView.swift
- Display bundled Welcome folder as if it were an open folder
- Same FolderBrowserView/MarkdownView components
- On launch when no folder is open

---

## Out of Scope (v1.0)

- Editing
- Persistence / recent files / projects
- iCloud sync
- Light mode
- Search
- Tabs
- Export/print
- Onboarding flows

---

## Verification

```bash
# Build
swift build

# Manual test
1. Launch → Welcome content shows
2. File > Open Folder → pick any folder with .md files
3. Sidebar shows files with drill-in/out
4. Click .md → content with syntax highlighting
5. Edit file externally → reload pill appears
6. Toggle AI Chat → ask "summarize this"
```

---

## Implementation Order

```
Phase 0: Cleanup          → Delete files, reorganize structure
Phase 1: Core Reading     → Folder browse + markdown view
Phase 2: File Watching    → FSEvents + reload pill
Phase 3: AI Chat          → Foundation Models integration
Phase 4: Welcome Content  → Bundled markdown files
```

All phases can run as a single Ralph loop with promise: "All phases complete, app launches with welcome content and all features work"
