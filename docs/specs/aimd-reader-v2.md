# QoL Improvements v2 - OOD-Aligned Specification

## Overview

Architectural refactoring + quality of life features for Pixley Markdown Reader, addressing OOD Wizard feedback. Creates reusable `aimdRenderer` Swift Package with pluggable rendering themes. Apple Foundation Models only (no external LLM providers).

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

## Phase 1.5: Pre-Refactor Cleanup (COMPLETE)

*Added 2026-02-04 based on SwiftUI Architecture Audit findings. These extractions prepare the codebase for the AppCoordinator refactor in Phase 2.*

### US-F2.1: Extract FolderTreeFilter Utility

**Description:** Extract tree filtering and search logic from view body to testable utility.

**Source:** ContentView.swift:240-260 (`filteredItems`, `findFirstMarkdown`)

**Acceptance Criteria:**
- [x] `FolderTreeFilter` struct created at `Sources/Services/FolderTreeFilter.swift`
- [x] `filterMarkdownOnly(_ items: [FolderItem]) -> [FolderItem]` method
- [x] `findFirstMarkdown(in items: [FolderItem]) -> FolderItem?` method
- [x] ContentView updated to use FolderTreeFilter instead of inline logic
- [x] Unit tests: happy path (filters correctly), edge case (empty folder), error (nil children)
- [x] App builds and file tree filtering works as before

---

### US-F2.2: Extract SecurityScopedBookmarkManager

**Description:** Consolidate duplicated security-scoped bookmark handling into single service.

**Source:** StartView.swift:167-199, AIMDReaderApp.swift (duplicated logic)

**Acceptance Criteria:**
- [x] `SecurityScopedBookmarkManager` class at `Sources/Services/SecurityScopedBookmarkManager.swift`
- [x] `getOrRequestAccess(to directory: FileManager.SearchPathDirectory) async -> URL?` method
- [x] `saveBookmark(_ url: URL, for directory: FileManager.SearchPathDirectory)` method
- [x] `resolveBookmark(for directory: FileManager.SearchPathDirectory) -> URL?` method
- [x] StartView and AIMDReaderApp updated to use manager
- [x] Unit tests: happy path, stale bookmark refresh, permission denied
- [x] App builds and folder shortcuts work as before

---

### US-F2.3: Extract ChatInputValidator

**Description:** Extract message validation and history management from ChatView.

**Source:** ChatView.swift:372-400 (validation, trimming, length check, history limiting)

**Acceptance Criteria:**
- [x] `ChatInputValidator` struct at `Sources/Services/ChatInputValidator.swift`
- [x] `validate(_ input: String) -> Result<String, ValidationError>` method
- [x] `ValidationError` enum with cases: `.empty`, `.tooLong(max: Int)`
- [x] `trimHistory(_ messages: [ChatMessage], max: Int) -> [ChatMessage]` method
- [x] ChatView updated to use validator
- [x] Unit tests: empty input, whitespace-only, exceeds 2000 chars, history trimming
- [x] App builds and chat validation works as before

---

### US-F2.4: Create ChatConfiguration Enum

**Description:** Centralize scattered chat-related constants.

**Source:** ChatView.swift:23,64-67, ChatService.swift (maxMessageHistory, maxTokens, etc.)

**Acceptance Criteria:**
- [x] `ChatConfiguration` enum at `Sources/Models/ChatConfiguration.swift`
- [x] `static let maxMessageHistory = 50`
- [x] `static let maxInputLength = 2000`
- [x] `static let maxContextTokens = 4096`
- [x] `static let charsPerToken = 4`
- [x] `static let maxContextChars = maxContextTokens * charsPerToken`
- [x] ChatView and ChatService updated to use ChatConfiguration
- [x] Unit tests: verify constants are accessible, computed properties correct
- [x] App builds and chat works as before

---

### US-F2.5: Fix Async Document Coordination

**Description:** Replace polling pattern with proper async/await coordination.

**Source:** ChatView.swift:337-369 (polling loop with exponential backoff)

**Acceptance Criteria:**
- [x] `AppState` gains `onDocumentLoaded: (@MainActor () -> Void)?` callback
- [x] `MarkdownView.loadFile()` calls `appState.onDocumentLoaded?()` after successful load
- [x] `ChatView.handleInitialQuestion()` awaits document via callback, not polling
- [x] Polling loop removed from ChatView
- [x] Unit tests: callback fires after load, timeout handling, nil callback (no-op)
- [x] App builds and initial chat question works when document loads

---

### US-F2.6: Add Status Bar Error UI

**Description:** Surface file operation errors to user instead of silent failure.

**Source:** MarkdownEditor.swift:102-121 (silent `print()` on size limit exceeded)

**Acceptance Criteria:**
- [x] `ErrorBanner` view created for status bar display
- [x] Error banner slides up from bottom when error occurs
- [x] Auto-dismisses after 5 seconds or manual dismiss via X button
- [x] Yellow indicator for warnings, red for errors
- [x] `AppState` gains `currentError: AppError?` property
- [x] MarkdownEditor sets `appState.currentError` instead of `print()`
- [x] Unit tests: error display, auto-dismiss timing, manual dismiss
- [x] App builds and shows error when opening file >10MB

**Verification:** `swift test` passes, app builds, manually test with large file

---

## Phase 1.6: Tech Debt Cleanup (COMPLETE)

*These issues were identified in the audit but are lower priority. Skip this phase if time-constrained.*

### US-F2.7: Fix MarkdownView Task Race Condition

**Description:** Consolidate dual `.task` modifiers that can race.

**Source:** MarkdownView.swift:41-48 (separate tasks for selectedFile and reloadTrigger)

**Acceptance Criteria:**
- [x] Single `.task(id:)` modifier watching tuple `(selectedFile, reloadTrigger)`
- [x] `loadFile()` called once per state change, not potentially twice
- [x] Unit tests: verify single load per change
- [x] App builds and file loading works as before

---

### US-F2.8: Fix NSTextViewDelegate Isolation

**Description:** Clean up MainActor boundary crossing in delegate.

**Source:** MarkdownEditor.swift:123-152 (nonisolated func with Task to MainActor)

**Acceptance Criteria:**
- [x] Delegate method properly isolated or synchronization explicit
- [x] Parent binding update happens synchronously where possible
- [x] Unit tests: verify text changes propagate correctly
- [x] App builds and text editing works as before

---

### US-F2.9: Fix RecentFoldersManager Stale Bookmark Duplicate

**Description:** Prevent duplicate entries when refreshing stale bookmark.

**Source:** RecentFoldersManager.swift:132-135 (addFolder called for stale refresh)

**Acceptance Criteria:**
- [x] `refreshStaleBookmark(_ folder: RecentFolder, url: URL)` method added
- [x] Updates bookmark in-place without creating duplicate entry
- [x] Unit tests: stale refresh doesn't duplicate, order preserved
- [x] App builds and recent folders work as before

---

### US-F2.10: Fix FolderService Cache Invalidation

**Description:** Invalidate parent folder caches when child changes.

**Source:** FolderService.swift:221-223 (markdown count stale after subfolder change)

**Acceptance Criteria:**
- [x] `invalidateCache(for url: URL)` also invalidates ancestor folders
- [x] Markdown counts update correctly after file add/delete
- [x] Unit tests: parent cache invalidated on child change
- [x] App builds and folder counts accurate after changes

---

## Phase 2: Foundation App (COMPLETE)

### US-F3: Theme/Renderer Protocol System

**Description:** Create pluggable theme system where themes are renderers.

**Acceptance Criteria:**
- [x] `MarkdownTheme` protocol with associated `Output` type
- [x] Protocol methods for each block type (heading, paragraph, code, etc.)
- [x] `SwiftUITheme` struct implementing protocol with `Output = AnyView`
- [x] 10+ syntax highlighting color schemes defined (Xcode Light, Xcode Dark, GitHub Light, GitHub Dark, One Dark, Dracula, Solarized Light, Solarized Dark, Monokai, Nord)
- [x] Theme renders markdown document to SwiftUI view hierarchy
- [x] Themes wired into app via SyntaxTheme/SyntaxPalette in MarkdownEditor + MarkdownHighlighter

**Implementation:** `Packages/aimdRenderer/Sources/aimdRenderer/Themes/`

---

### US-F4: AppCoordinator and State Decomposition

**Description:** Refactor AppState into focused state containers owned by AppCoordinator.

**Acceptance Criteria:**
- [x] `AppCoordinator` class created as single owner of state
- [x] `NavigationState`: `rootFolderURL`, `selectedFile`
- [x] `UIState`: `isAIChatVisible`, panel visibility flags
- [x] `DocumentState`: `documentModel: DocumentModel`, `fileHasChanges`, `reloadTrigger`
- [x] Old `AppState` kept for backward compatibility (marked for future deprecation)
- [x] All views updated to use new state containers via Environment (gradual migration)
- [x] App launches and functions as before

**Implementation:** `Sources/Coordinator/AppCoordinator.swift`

---

### US-F5: SettingsRepository Abstraction

**Description:** Create protocol-based settings access replacing scattered @AppStorage.

**Acceptance Criteria:**
- [x] `SettingsRepository` protocol defined
- [x] `AppearanceSettings`: colorScheme
- [x] `RenderingSettings`: fontSize, fontFamily, syntaxTheme, headingScale, showLineNumbers
- [x] `BehaviorSettings`: linkBehavior
- [x] `UserDefaultsSettingsRepository` implementation using UserDefaults
- [x] All views access settings through repository
- [x] Settings types match aimdRenderer theme types

**Implementation:** `Sources/Settings/SettingsRepository.swift`

---

## Phase 3: Persistence (COMPLETE)

### US-F6: FileMetadataRepository with SwiftData

**Description:** Create persistence layer for reading state using SwiftData.

**Acceptance Criteria:**
- [x] `FileMetadataRepository` protocol defined
- [x] `FileMetadata` SwiftData model: fileURL, scrollPosition, isFavorite, lastOpened
- [x] `Bookmark` SwiftData model: fileURL, lineNumber, note (optional)
- [x] `SwiftDataMetadataRepository` implementation
- [x] Can save and retrieve scroll position for a file
- [x] Can mark file as favorite and retrieve favorites list
- [x] Can create and retrieve bookmarks for a file
- [x] Schema versioning (SchemaV1) and migration plan defined
- [x] Wired into AppCoordinator via modelContext injection in AIMDReaderApp

**Implementation:** `Sources/Persistence/`

---

## Phase 4: Epic 1 - Settings & Customization (COMPLETE)

### US-1.1: Settings Window Infrastructure

**Description:** Create Settings window accessible via Cmd+, with tabbed interface.

**Acceptance Criteria:**
- [x] Cmd+, opens Settings window from any app state (via SwiftUI Settings scene)
- [x] Window has tabs: Appearance (merged with Rendering), Behavior
- [x] Settings persist after app restart
- [x] Uses SettingsRepository from Foundation

---

### US-1.2: Appearance & Rendering Settings Tab

**Description:** Dark/light mode, font, theme, and display options — merged from spec's Appearance + Rendering tabs.

**Acceptance Criteria:**
- [x] Color scheme picker (Light, Dark, System)
- [x] Syntax theme picker showing all 10+ themes
- [x] Font family picker (system, serif, sans-serif, monospace options)
- [x] Font size slider
- [x] Heading scale picker (compact, normal, spacious)
- [x] Line numbers toggle (show/hide document gutter)
- [x] Changes apply immediately to open document

---

### US-1.3: Behavior Settings Tab

**Description:** Link behavior and interaction preferences.

**Acceptance Criteria:**
- [x] Link behavior: open in browser vs. in-app handling
- [x] Link underline toggle
- [x] Settings persist via SettingsRepository

---

## Phase 5: Epic 2 - Search & Navigation (COMPLETE)

### US-2.1: File Tree Filter

**Description:** Search field in sidebar to filter file tree by filename.

**Acceptance Criteria:**
- [x] Search field in sidebar header (with magnifying glass icon)
- [x] Typing filters visible files immediately (150ms debounce)
- [x] Partial matches supported (e.g., "read" matches "README.md")
- [x] Parent folders of matches remain visible
- [x] Clear button resets filter
- [x] Favorites-only filter toggle (star icon)

---

### US-2.2: Content Search & Navigation (Cmd+F / Cmd+G)

**Description:** Find in document with match navigation. Implemented via native NSTextView find bar.

*Note: Originally two stories (US-2.2 Content Search, US-2.3 Search Navigation). Merged because the native find bar covers both — Cmd+F opens it, Cmd+G/Cmd+Shift+G navigate matches, Escape closes it.*

**Acceptance Criteria:**
- [x] Cmd+F opens find bar in document view (usesFindBar = true)
- [x] Incremental search enabled (isIncrementalSearchingEnabled = true)
- [x] All matches highlighted
- [x] Cmd+G advances to next match, Cmd+Shift+G to previous (native behavior)
- [x] Escape closes find bar

---

### US-2.3: File Tree Keyboard Navigation

**Description:** Arrow key navigation in file tree.

**Acceptance Criteria:**
- [x] Up/Down arrows move selection (native NSOutlineView)
- [x] Left/Right arrows collapse/expand folders (native NSOutlineView)
- [x] Return toggles folder expansion (KeyHandlingOutlineView)
- [x] Escape deselects (KeyHandlingOutlineView)
- [x] Selection visually highlighted

---

### US-2.4: Quick Switcher (Cmd+P)

**Description:** Fuzzy file finder overlay.

**Acceptance Criteria:**
- [x] Cmd+P opens modal overlay with search field
- [x] Fuzzy/prefix matching on filenames (prefix scores 2, contains scores 1)
- [x] Results sorted by relevance (top 20)
- [x] Up/Down navigate results
- [x] Enter opens selected file and closes overlay
- [x] Escape closes overlay

---

## Phase 6: Epic 4 - Reading Experience (COMPLETE)

### US-4.1: Reading Progress Persistence

**Description:** Remember scroll position per file using FileMetadataRepository.

**Acceptance Criteria:**
- [x] Scroll position saved when leaving file
- [x] Scroll position restored when reopening file
- [x] Position persists across app restart (SwiftData)
- [x] New files start at top

---

### US-4.2: Reading Progress Indicator

**Description:** Visual indicator of reading progress.

**Acceptance Criteria:**
- [x] ReadingProgressBadge visible in top-right corner
- [x] Accurately reflects scroll position as percentage
- [x] Does not obstruct content
- [x] Updates in real-time while scrolling

---

### US-4.3: File Favorites

**Description:** Star files for quick access using FileMetadataRepository.

**Acceptance Criteria:**
- [x] Star icon on file rows in sidebar (FileCellView)
- [x] Click toggles favorite status
- [x] Favorites-only filter toggle in sidebar
- [x] Favorites persist via SwiftData
- [x] Can unfavorite by clicking star again

---

### US-4.4: Line Bookmarks

**Description:** Bookmark specific lines using FileMetadataRepository.

**Acceptance Criteria:**
- [x] Click in gutter to add bookmark at line (LineNumberRulerView)
- [x] Bookmarked lines have orange dot marker in gutter
- [x] Bookmarked line numbers displayed in orange
- [x] Can delete bookmarks by clicking gutter again
- [x] Bookmarks persist via SwiftData

---

### US-4.5: File Watching

**Description:** Monitor open file for external changes.

**Acceptance Criteria:**
- [x] File changes detected via DispatchSource (.write, .rename, .delete events)
- [x] Reload pill appears when file modified externally
- [x] Click pill reloads content
- [x] Debounce via modificationDate comparison prevents false positives

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

## Implementation Phases (ALL COMPLETE)

### Phase 1: Foundation Package (COMPLETE)
- US-F1: aimdRenderer package + DocumentModel
- US-F2: AST parsing with swift-markdown

### Phase 1.5: Pre-Refactor Cleanup (COMPLETE)
- US-F2.1 through US-F2.6: All extractions and fixes applied

### Phase 1.6: Tech Debt Cleanup (COMPLETE)
- US-F2.7 through US-F2.10: All fixes applied

### Phase 2: Foundation App (COMPLETE)
- US-F3: Theme/Renderer protocol + SyntaxTheme wired into app
- US-F4: AppCoordinator + state decomposition, environment-injected
- US-F5: SettingsRepository driving all views

### Phase 3: Persistence (COMPLETE)
- US-F6: FileMetadataRepository with SwiftData, wired into AppCoordinator

### Phase 4: Epic 1 - Settings (COMPLETE)
- US-1.1: Settings window (Cmd+,)
- US-1.2: Appearance & Rendering tab (merged)
- US-1.3: Behavior tab

### Phase 5: Epic 2 - Search (COMPLETE)
- US-2.1: File tree filter with debounce
- US-2.2: Content search & navigation (native find bar — Cmd+F/G)
- US-2.3: File tree keyboard navigation
- US-2.4: Quick switcher (Cmd+P)

### Phase 6: Epic 4 - Reading (COMPLETE)
- US-4.1: Scroll position persistence
- US-4.2: Reading progress badge
- US-4.3: File favorites
- US-4.4: Line bookmarks
- US-4.5: File watching

---

## Future (v3.0)

- **applacatCanvas Package**: Multi-block canvas for layouts
- **Split View**: Two content blocks side-by-side via applacatCanvas
- **HTML/PDF Renderers**: Additional theme implementations
- **LLM Provider Protocol**: When external providers needed
