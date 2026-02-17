# OOD Wizard Recommendations — Implementation Spec

**Source:** `scratch/audit-ood-wizard-2026-02-05.md`
**Date:** 2026-02-05
**Scope:** 5 fixes from 10 findings (5 skipped by decision)

---

## Decisions Summary

| # | Finding | Decision | Rationale |
|---|---------|----------|-----------|
| 1 | Document content triple-ownership | **FIX** | DocumentState becomes authoritative file loader |
| 2 | Duplicated Welcome folder logic | **FIX** | Extract to shared utility |
| 3 | Settings containers embed UserDefaults | **FIX** | Pure data + repository handles persistence |
| 4 | Two mutation paths | **FIX** | All mutations through coordinator |
| 5 | Singleton services bypass coordinator | **SKIP** | No tests planned, pragmatic |
| 6 | SettingsRepository protocol unused | **SKIP** | Keep as-is for future |
| 7 | UIState.showError auto-dismiss | **FIX** | Move to view .task modifier |
| 8 | NavigationState security scope | **SKIP** | Pragmatic coupling for macOS |
| 9 | FolderItem as NSOutlineView items | **SKIP** | Known cost, no action |
| 10 | ChatView creates ChatService inline | **SKIP** | Fresh chat on toggle is fine |

---

## User Stories

### US-1: DocumentState as File-Loading Authority

**What:** DocumentState becomes the single source of truth for document content. It loads files. MarkdownView reads from it instead of loading independently.

**Why:** Currently document content exists in three places: `DocumentState.content`, `MarkdownView.content` (@State), and `NSTextView.string`. The first two are redundant. DocumentState should own the data; MarkdownView should consume it.

**Changes:**
1. Add a `loadFile(url:)` async method to `DocumentState` that reads file content via `Task.detached` (to keep file I/O off main thread)
2. Remove `@State private var content` from `MarkdownView`
3. `MarkdownView` reads `coordinator.document.content` instead of its own @State
4. Remove `coordinator.setDocumentContent()` calls from MarkdownView — DocumentState already has the content because it loaded it
5. `NSTextView.string` remains (unavoidable — AppKit needs its own copy)
6. Wire the coordinator's `selectFile()` or equivalent to call `document.loadFile(url:)`

**Acceptance Criteria:**
- `DocumentState.content` is set by DocumentState's own `loadFile()`, not by MarkdownView pushing to it
- MarkdownView has no `@State` for document content
- ChatView still reads document content from `coordinator.document.content`
- NSTextView still renders correctly
- App builds with 0 warnings

### US-2: Extract Welcome Folder Logic

**What:** `ensureWelcomeFolder()` and `welcomeFolderURL` are duplicated between `AIMDReaderApp` and `StartView`. Extract to a shared utility.

**Changes:**
1. Create a `WelcomeManager` type (or static methods on an existing type) with `ensureWelcomeFolder()` and `welcomeFolderURL`
2. Both `AIMDReaderApp` and `StartView` call the shared implementation
3. Delete duplicated code from both files

**Acceptance Criteria:**
- `ensureWelcomeFolder()` exists in exactly one place
- `welcomeFolderURL` exists in exactly one place
- Both AIMDReaderApp and StartView use the shared version
- Welcome folder still works (click mascot → opens tour)

### US-3: Settings Containers as Pure Data

**What:** Remove `UserDefaults` persistence logic from `AppearanceSettings`, `RenderingSettings`, and `BehaviorSettings`. Move all persistence into `UserDefaultsSettingsRepository`.

**Why:** The settings containers currently have `UserDefaults.standard` hardcoded in `init` (to read) and `didSet` (to write). This undermines the `SettingsRepository` protocol abstraction. The containers should be pure observable data; the repository should handle persistence.

**Changes:**
1. Remove `UserDefaults.standard.set(...)` from all `didSet` in settings container properties
2. Remove `UserDefaults.standard.value(forKey:)` from all `init` in settings containers
3. Settings containers become plain `@Observable` classes with default values
4. `UserDefaultsSettingsRepository` is responsible for:
   - Loading saved values into settings containers on init
   - Observing changes and persisting them (e.g., via `withObservationTracking` or explicit save methods)
5. The repository is the only type that touches `UserDefaults`

**Acceptance Criteria:**
- No `UserDefaults` imports or references in settings container classes
- `UserDefaultsSettingsRepository` handles all read/write
- Settings persist across app launches (same behavior as before)
- Creating a settings container in isolation does NOT read from UserDefaults (testable)

### US-4: All Mutations Through Coordinator

**What:** Make state container properties private/internal to the module. All view-level state mutations go through coordinator methods.

**Why:** Currently views can mutate state two ways: via coordinator methods OR by reaching through to container properties (e.g., `coordinator.navigation.sidebarFilterQuery = x`). This creates ambiguity about where state changes happen.

**Changes:**
1. Audit all direct property assignments on `coordinator.navigation.*`, `coordinator.ui.*`, `coordinator.document.*` across all views
2. For each direct assignment, create a coordinator method (or use an existing one)
3. Make mutable properties on NavigationState, UIState, DocumentState `internal` or `private(set)` so views cannot set them directly
4. Views continue to READ container properties freely (observation still works)
5. **Semantic methods** for coordinator API: meaningful names for meaningful actions (e.g., `closeBrowser()`, `openFolder(url:)`). For simple property bindings that views need for two-way binding, expose as computed properties with setters on the coordinator rather than methods

**Acceptance Criteria:**
- No view file directly assigns a property on a state container (grep test: no `coordinator.navigation.someProperty =` or `coordinator.ui.someProperty =` in view files)
- All state mutations go through coordinator methods
- State container mutable properties are not publicly settable from outside the coordinator
- App behavior unchanged

### US-5: Error Auto-Dismiss to View .task

**What:** Move the error auto-dismiss timer from `UIState` (stored Task) to the view layer using `.task` modifier.

**Why:** The current pattern stores a `Task` in `UIState` to auto-dismiss errors after a delay. This is fragile if UIState is recreated. Error display timing is a view concern, not a state concern.

**Changes:**
1. Remove the auto-dismiss `Task` and its cancellation from `UIState.showError()`
2. `UIState.showError()` just sets the error and nothing else
3. In the view that displays the error, add a `.task(id: error)` modifier that waits and then clears the error
4. Remove `[weak self]` pattern from UIState (no longer needed for this)

**Acceptance Criteria:**
- `UIState` has no stored `Task` for error dismissal
- Error still auto-dismisses after the same delay
- Error can still be manually dismissed

---

## Implementation Approach

**Single pass** — all 5 stories in one focused session.

**Suggested order** (not phased, but logical dependency):
1. **US-2** first (Welcome folder extraction) — smallest, independent, warm-up
2. **US-5** next (error .task) — small, independent
3. **US-1** (DocumentState authority) — biggest change, foundational
4. **US-3** (Settings pure data) — independent of US-1
5. **US-4** last (all through coordinator) — depends on US-1 being done since DocumentState's API changes

**Verification after each story:**
- `swift build` passes with 0 errors
- App launches and basic flow works (open folder → select file → view markdown → toggle chat)

---

## Out of Scope

- Singleton service injection (#5) — deferred until testing becomes a priority
- SettingsRepository protocol usage (#6) — kept as-is
- NavigationState security scope coupling (#8) — pragmatic for macOS
- FolderItem struct identity (#9) — known cost
- ChatService ownership (#10) — fresh chat is acceptable behavior
- Any new features — this is purely architectural cleanup
