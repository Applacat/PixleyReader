# QoL Improvements v2 - OOD-Aligned Specification

## Overview

Architectural refactoring + quality of life features for AI.md Reader, addressing OOD Wizard feedback. Creates reusable `aimdRenderer` Swift Package with pluggable rendering themes. Apple Foundation Models only (no external LLM providers).

## Vision

Build a markdown rendering package (`aimdRenderer`) that:
1. Parses markdown into structured building blocks (AST)
2. Supports pluggable "themes" that are actually **renderers** (SwiftUI theme, HTML theme, PDF theme, etc.)
3. Can power content blocks across websites, SaaS products, and native apps

Future: `applacatCanvas` package will consume aimdRenderer blocks for multi-block layouts (v2.0/v3.0).

---

## Scope

### In Scope
- **Foundation Phase**: AppCoordinator pattern, state decomposition, SettingsRepository, aimdRenderer package
- **Phase 1.5**: Pre-refactor cleanup (audit fixes) - 6 HIGH priority extractions
- **Phase 1.6**: Tech debt cleanup (optional) - 5 MEDIUM priority fixes
- **Epic 1**: Settings & Customization (Settings window, themes, fonts, line numbers)
- **Epic 2**: Search & Navigation (file filter, Cmd+F, quick switcher, keyboard nav)
- **Epic 4**: Reading Experience (progress persistence, favorites, bookmarks, file watching)

### Out of Scope
- Epic 3 (LLM Provider Support) - keeping Apple Foundation Models only
- Claude API, OpenAI API, MLX local models
- LLMProvider protocol (deferred until multiple providers needed)
- iCloud sync
- Export/share functionality
- HTML/PDF renderers (architecture supports them, not building yet)
- Split View (deferred to applacatCanvas in v2.0/v3.0)

---

## Phase 1: Foundation Package (COMPLETE)

### US-F1: Create aimdRenderer Package with DocumentModel

**Description:** Create local Swift Package `aimdRenderer` with basic DocumentModel structure.

**Acceptance Criteria:**
- [x] Swift Package created at `Packages/aimdRenderer`
- [x] `DocumentModel` struct with `content: String` and `lines: [Line]`
- [x] `Line` struct with `number: Int`, `range: Range<String.Index>`, `content: Substring`
- [x] Package builds: `swift build` succeeds
- [x] Main app imports aimdRenderer successfully

---

### US-F2: Add AST Parsing with swift-markdown

**Description:** Integrate Apple's swift-markdown for AST parsing in aimdRenderer.

**Acceptance Criteria:**
- [x] swift-markdown added as package dependency
- [x] `MarkdownAST` type wraps parsed document
- [x] `DocumentModel` includes `ast: MarkdownAST`
- [x] Can parse markdown string and access headings, code blocks, paragraphs
- [x] Unit tests pass for basic markdown parsing

---

## Phase 1.5: Pre-Refactor Cleanup (HIGH Priority)

*Added 2026-02-04 based on SwiftUI Architecture Audit findings. These extractions prepare the codebase for the AppCoordinator refactor in Phase 2.*

### US-F2.1: Extract FolderTreeFilter Utility

**Description:** Extract tree filtering and search logic from view body to testable utility.

**Source:** ContentView.swift:240-260 (`filteredItems`, `findFirstMarkdown`)

**Acceptance Criteria:**
- [ ] `FolderTreeFilter` struct created at `Sources/Services/FolderTreeFilter.swift`
- [ ] `filterMarkdownOnly(_ items: [FolderItem]) -> [FolderItem]` method
- [ ] `findFirstMarkdown(in items: [FolderItem]) -> FolderItem?` method
- [ ] ContentView updated to use FolderTreeFilter instead of inline logic
- [ ] Unit tests: happy path (filters correctly), edge case (empty folder), error (nil children)
- [ ] App builds and file tree filtering works as before

---

### US-F2.2: Extract SecurityScopedBookmarkManager

**Description:** Consolidate duplicated security-scoped bookmark handling into single service.

**Source:** StartView.swift:167-199, AIMDReaderApp.swift (duplicated logic)

**Acceptance Criteria:**
- [ ] `SecurityScopedBookmarkManager` class at `Sources/Services/SecurityScopedBookmarkManager.swift`
- [ ] `getOrRequestAccess(to directory: FileManager.SearchPathDirectory) async -> URL?` method
- [ ] `saveBookmark(_ url: URL, for directory: FileManager.SearchPathDirectory)` method
- [ ] `resolveBookmark(for directory: FileManager.SearchPathDirectory) -> URL?` method
- [ ] StartView and AIMDReaderApp updated to use manager
- [ ] Unit tests: happy path, stale bookmark refresh, permission denied
- [ ] App builds and folder shortcuts work as before

---

### US-F2.3: Extract ChatInputValidator

**Description:** Extract message validation and history management from ChatView.

**Source:** ChatView.swift:372-400 (validation, trimming, length check, history limiting)

**Acceptance Criteria:**
- [ ] `ChatInputValidator` struct at `Sources/Services/ChatInputValidator.swift`
- [ ] `validate(_ input: String) -> Result<String, ValidationError>` method
- [ ] `ValidationError` enum with cases: `.empty`, `.tooLong(max: Int)`
- [ ] `trimHistory(_ messages: [ChatMessage], max: Int) -> [ChatMessage]` method
- [ ] ChatView updated to use validator
- [ ] Unit tests: empty input, whitespace-only, exceeds 2000 chars, history trimming
- [ ] App builds and chat validation works as before

---

### US-F2.4: Create ChatConfiguration Enum

**Description:** Centralize scattered chat-related constants.

**Source:** ChatView.swift:23,64-67, ChatService.swift (maxMessageHistory, maxTokens, etc.)

**Acceptance Criteria:**
- [ ] `ChatConfiguration` enum at `Sources/Models/ChatConfiguration.swift`
- [ ] `static let maxMessageHistory = 50`
- [ ] `static let maxInputLength = 2000`
- [ ] `static let maxContextTokens = 4096`
- [ ] `static let charsPerToken = 4`
- [ ] `static let maxContextChars = maxContextTokens * charsPerToken`
- [ ] ChatView and ChatService updated to use ChatConfiguration
- [ ] Unit tests: verify constants are accessible, computed properties correct
- [ ] App builds and chat works as before

---

### US-F2.5: Fix Async Document Coordination

**Description:** Replace polling pattern with proper async/await coordination.

**Source:** ChatView.swift:337-369 (polling loop with exponential backoff)

**Acceptance Criteria:**
- [ ] `AppState` gains `onDocumentLoaded: (@MainActor () -> Void)?` callback
- [ ] `MarkdownView.loadFile()` calls `appState.onDocumentLoaded?()` after successful load
- [ ] `ChatView.handleInitialQuestion()` awaits document via callback, not polling
- [ ] Polling loop removed from ChatView
- [ ] Unit tests: callback fires after load, timeout handling, nil callback (no-op)
- [ ] App builds and initial chat question works when document loads

---

### US-F2.6: Add Status Bar Error UI

**Description:** Surface file operation errors to user instead of silent failure.

**Source:** MarkdownEditor.swift:102-121 (silent `print()` on size limit exceeded)

**Acceptance Criteria:**
- [ ] `ErrorBanner` view created for status bar display
- [ ] Error banner slides up from bottom when error occurs
- [ ] Auto-dismisses after 5 seconds or manual dismiss via X button
- [ ] Yellow indicator for warnings, red for errors
- [ ] `AppState` gains `currentError: AppError?` property
- [ ] MarkdownEditor sets `appState.currentError` instead of `print()`
- [ ] Unit tests: error display, auto-dismiss timing, manual dismiss
- [ ] App builds and shows error when opening file >10MB

**Verification:** `swift test` passes, app builds, manually test with large file

---

## Phase 1.6: Tech Debt Cleanup (MEDIUM Priority, Optional)

*These issues were identified in the audit but are lower priority. Skip this phase if time-constrained.*

### US-F2.7: Fix MarkdownView Task Race Condition

**Description:** Consolidate dual `.task` modifiers that can race.

**Source:** MarkdownView.swift:41-48 (separate tasks for selectedFile and reloadTrigger)

**Acceptance Criteria:**
- [ ] Single `.task(id:)` modifier watching tuple `(selectedFile, reloadTrigger)`
- [ ] `loadFile()` called once per state change, not potentially twice
- [ ] Unit tests: verify single load per change
- [ ] App builds and file loading works as before

---

### US-F2.8: Fix NSTextViewDelegate Isolation

**Description:** Clean up MainActor boundary crossing in delegate.

**Source:** MarkdownEditor.swift:123-152 (nonisolated func with Task to MainActor)

**Acceptance Criteria:**
- [ ] Delegate method properly isolated or synchronization explicit
- [ ] Parent binding update happens synchronously where possible
- [ ] Unit tests: verify text changes propagate correctly
- [ ] App builds and text editing works as before

---

### US-F2.9: Fix RecentFoldersManager Stale Bookmark Duplicate

**Description:** Prevent duplicate entries when refreshing stale bookmark.

**Source:** RecentFoldersManager.swift:132-135 (addFolder called for stale refresh)

**Acceptance Criteria:**
- [ ] `refreshStaleBookmark(_ folder: RecentFolder, url: URL)` method added
- [ ] Updates bookmark in-place without creating duplicate entry
- [ ] Unit tests: stale refresh doesn't duplicate, order preserved
- [ ] App builds and recent folders work as before

---

### US-F2.10: Fix FolderService Cache Invalidation

**Description:** Invalidate parent folder caches when child changes.

**Source:** FolderService.swift:221-223 (markdown count stale after subfolder change)

**Acceptance Criteria:**
- [ ] `invalidateCache(for url: URL)` also invalidates ancestor folders
- [ ] Markdown counts update correctly after file add/delete
- [ ] Unit tests: parent cache invalidated on child change
- [ ] App builds and folder counts accurate after changes

---

## Phase 2: Foundation App

### US-F3: Theme/Renderer Protocol System

**Description:** Create pluggable theme system where themes are renderers.

**Acceptance Criteria:**
- [ ] `MarkdownTheme` protocol with associated `Output` type
- [ ] Protocol methods for each block type (heading, paragraph, code, etc.)
- [ ] `SwiftUITheme` struct implementing protocol with `Output = AnyView`
- [ ] 10+ syntax highlighting color schemes defined (Xcode Light, Xcode Dark, GitHub Light, GitHub Dark, One Dark, Dracula, Solarized Light, Solarized Dark, Monokai, Nord)
- [ ] Theme renders markdown document to SwiftUI view hierarchy

---

### US-F4: AppCoordinator and State Decomposition

**Description:** Refactor AppState into focused state containers owned by AppCoordinator.

**Acceptance Criteria:**
- [ ] `AppCoordinator` class created as single owner of state
- [ ] `NavigationState`: `rootFolderURL`, `selectedFile`
- [ ] `UIState`: `isAIChatVisible`, panel visibility flags
- [ ] `DocumentState`: `documentModel: DocumentModel`, `fileHasChanges`, `reloadTrigger`
- [ ] Old `AppState` removed or deprecated
- [ ] All views updated to use new state containers via Environment
- [ ] App launches and functions as before

---

### US-F5: SettingsRepository Abstraction

**Description:** Create protocol-based settings access replacing scattered @AppStorage.

**Acceptance Criteria:**
- [ ] `SettingsRepository` protocol defined
- [ ] `AppearanceSettings`: colorScheme
- [ ] `RenderingSettings`: fontSize, fontFamily, syntaxTheme, headingScale, showLineNumbers
- [ ] `BehaviorSettings`: linkBehavior
- [ ] `UserDefaultsSettingsRepository` implementation using @AppStorage internally
- [ ] All views access settings through repository, not direct @AppStorage
- [ ] Existing settings (fontSize, colorScheme) migrated to new system

---

## Phase 3: Persistence

### US-F6: FileMetadataRepository with SwiftData

**Description:** Create persistence layer for reading state using SwiftData.

**Acceptance Criteria:**
- [ ] `FileMetadataRepository` protocol defined
- [ ] `FileMetadata` SwiftData model: fileURL, scrollPosition, isFavorite, lastOpened
- [ ] `Bookmark` SwiftData model: fileURL, lineNumber, note (optional)
- [ ] `SwiftDataMetadataRepository` implementation
- [ ] Can save and retrieve scroll position for a file
- [ ] Can mark file as favorite and retrieve favorites list
- [ ] Can create and retrieve bookmarks for a file

---

## Phase 4: Epic 1 - Settings & Customization

### US-1.1: Settings Window Infrastructure

**Description:** Create Settings window accessible via Cmd+, with tabbed interface.

**Acceptance Criteria:**
- [ ] Cmd+, opens Settings window from any app state
- [ ] Window has tabs: Appearance, Rendering, Behavior
- [ ] Settings persist after app restart
- [ ] Uses SettingsRepository from Foundation

---

### US-1.2: Appearance Settings Tab

**Description:** Dark/light mode and appearance options in Settings.

**Acceptance Criteria:**
- [ ] Color scheme picker (Light, Dark, System)
- [ ] Toggle syncs with toolbar appearance button
- [ ] Changes apply immediately without restart

---

### US-1.3: Rendering Settings Tab

**Description:** Font, theme, and display options for markdown rendering.

**Acceptance Criteria:**
- [ ] Syntax theme picker showing all 10+ themes with preview
- [ ] Font family picker (system, serif, sans-serif, monospace options)
- [ ] Font size slider (already exists in toolbar, also accessible here)
- [ ] Heading scale picker (compact, normal, spacious)
- [ ] Line numbers toggle (show/hide document gutter)
- [ ] Changes apply immediately to open document

---

### US-1.4: Behavior Settings Tab

**Description:** Link behavior and interaction preferences.

**Acceptance Criteria:**
- [ ] Link behavior: open in browser vs. in-app handling
- [ ] Link underline toggle
- [ ] Settings persist via SettingsRepository

---

## Phase 5: Epic 2 - Search & Navigation

### US-2.1: File Tree Filter

**Description:** Search field in sidebar to filter file tree by filename.

**Acceptance Criteria:**
- [ ] Search field in sidebar header
- [ ] Typing filters visible files immediately
- [ ] Partial matches supported (e.g., "read" matches "README.md")
- [ ] Parent folders of matches remain visible
- [ ] Clear button resets filter
- [ ] Empty state when no matches

---

### US-2.2: Content Search (Cmd+F)

**Description:** Find in document using DocumentModel.

**Acceptance Criteria:**
- [ ] Cmd+F opens search overlay in document view
- [ ] Search uses DocumentModel.lines for matching
- [ ] All matches highlighted with visible background
- [ ] Match count displayed (e.g., "3 of 12")
- [ ] Escape closes search overlay

---

### US-2.3: Search Navigation (Cmd+G)

**Description:** Navigate between search matches.

**Acceptance Criteria:**
- [ ] Cmd+G advances to next match
- [ ] Cmd+Shift+G goes to previous match
- [ ] Current match visually distinct from other matches
- [ ] Document scrolls to keep current match visible
- [ ] Wraps from last to first match

---

### US-2.4: File Tree Keyboard Navigation

**Description:** Arrow key navigation in file tree.

**Acceptance Criteria:**
- [ ] Up/Down arrows move selection
- [ ] Left arrow collapses folder
- [ ] Right arrow expands folder
- [ ] Enter opens selected file
- [ ] Escape deselects
- [ ] Selection visually highlighted

---

### US-2.5: Quick Switcher (Cmd+P)

**Description:** Fuzzy file finder overlay.

**Acceptance Criteria:**
- [ ] Cmd+P opens modal overlay with search field
- [ ] Fuzzy matching on filenames (e.g., "cv" matches "ContentView.swift")
- [ ] Results sorted by relevance
- [ ] Up/Down navigate results
- [ ] Enter opens selected file and closes overlay
- [ ] Escape closes overlay

---

## Phase 6: Epic 4 - Reading Experience

### US-4.1: Reading Progress Persistence

**Description:** Remember scroll position per file using FileMetadataRepository.

**Acceptance Criteria:**
- [ ] Scroll position saved when leaving file
- [ ] Scroll position restored when reopening file
- [ ] Position persists across app restart (SwiftData)
- [ ] New files start at top

---

### US-4.2: Reading Progress Indicator

**Description:** Visual indicator of reading progress.

**Acceptance Criteria:**
- [ ] Progress indicator visible in toolbar or scrollbar area
- [ ] Accurately reflects scroll position as percentage
- [ ] Does not obstruct content
- [ ] Updates in real-time while scrolling

---

### US-4.3: File Favorites

**Description:** Star files for quick access using FileMetadataRepository.

**Acceptance Criteria:**
- [ ] Star icon on file rows in sidebar
- [ ] Click toggles favorite status
- [ ] Favorites section at top of sidebar (or filter option)
- [ ] Favorites persist via SwiftData
- [ ] Can unfavorite from favorites section

---

### US-4.4: Line Bookmarks

**Description:** Bookmark specific lines using FileMetadataRepository.

**Acceptance Criteria:**
- [ ] Click in gutter to add bookmark at line
- [ ] Bookmarked lines have visible marker in gutter
- [ ] Bookmarks panel/list shows all bookmarks for current file
- [ ] Click bookmark in list jumps to line
- [ ] Can delete bookmarks
- [ ] Bookmarks persist via SwiftData

---

### US-4.5: File Watching

**Description:** Monitor open file for external changes.

**Acceptance Criteria:**
- [ ] File changes detected within 2 seconds
- [ ] Existing "reload pill" appears when file modified externally
- [ ] Click pill reloads content
- [ ] No false positives from internal operations
- [ ] Uses DispatchSource or FSEvents

---

## Technical Notes

### aimdRenderer Package Structure
```
Packages/aimdRenderer/
├── Package.swift
├── Sources/aimdRenderer/
│   ├── Models/
│   │   ├── DocumentModel.swift
│   │   ├── Line.swift
│   │   └── MarkdownAST.swift
│   ├── Themes/
│   │   ├── MarkdownTheme.swift
│   │   ├── SwiftUITheme.swift
│   │   └── SyntaxThemes/
│   │       ├── XcodeTheme.swift
│   │       ├── GitHubTheme.swift
│   │       └── ... (10+ themes)
│   └── Parsing/
│       └── MarkdownParser.swift
└── Tests/
```

### AppCoordinator Structure
```swift
@MainActor @Observable
final class AppCoordinator {
    let navigation: NavigationState
    let ui: UIState
    let document: DocumentState
    let settings: SettingsRepository
    let metadata: FileMetadataRepository
}
```

### Dependencies
- Apple swift-markdown (for AST parsing)
- SwiftData (for persistence)

---

## Verification

### Commands
```bash
# Build packages
swift build

# Run tests
swift test

# Build app
xcodebuild -scheme AIMDReader build
```

### Manual Verification
- App launches without errors
- All existing functionality works (file browsing, markdown viewing, AI chat)
- Settings window opens with Cmd+,
- Search works with Cmd+F
- Quick switcher works with Cmd+P
- Reading progress persists across sessions

---

## Implementation Phases

### Phase 1: Foundation Package (COMPLETE)
- US-F1: aimdRenderer package + DocumentModel
- US-F2: AST parsing with swift-markdown
- **Verification:** `swift build` in Packages/aimdRenderer

### Phase 1.5: Pre-Refactor Cleanup (HIGH Priority)
- US-F2.1: Extract FolderTreeFilter utility
- US-F2.2: Extract SecurityScopedBookmarkManager
- US-F2.3: Extract ChatInputValidator
- US-F2.4: Create ChatConfiguration enum
- US-F2.5: Fix async document coordination
- US-F2.6: Add status bar error UI
- **Verification:** `swift test` passes, app builds and launches, all existing features work

### Phase 1.6: Tech Debt Cleanup (MEDIUM Priority, Optional)
- US-F2.7: Fix MarkdownView task race condition
- US-F2.8: Fix NSTextViewDelegate isolation
- US-F2.9: Fix RecentFoldersManager stale bookmark duplicate
- US-F2.10: Fix FolderService cache invalidation
- **Verification:** `swift test` passes, app builds

### Phase 2: Foundation App
- US-F3: Theme/Renderer protocol + SwiftUI theme
- US-F4: AppCoordinator + state decomposition
- US-F5: SettingsRepository
- **Verification:** App builds and launches, existing features work

### Phase 3: Persistence
- US-F6: FileMetadataRepository with SwiftData
- **Verification:** Can save/retrieve test metadata

### Phase 4: Epic 1 (Settings)
- US-1.1 through US-1.4
- **Verification:** Settings window functional, changes persist

### Phase 5: Epic 2 (Search)
- US-2.1 through US-2.5
- **Verification:** All search features work

### Phase 6: Epic 4 (Reading)
- US-4.1 through US-4.5
- **Verification:** Progress, favorites, bookmarks, file watching all functional

---

## Future (v2.0/v3.0)

- **applacatCanvas Package**: Multi-block canvas for layouts
- **Split View**: Two content blocks side-by-side via applacatCanvas
- **HTML/PDF Renderers**: Additional theme implementations
- **LLM Provider Protocol**: When external providers needed
