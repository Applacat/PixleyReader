# Implement All Audit Fixes — v2.0 Pre-Release

**Status:** PENDING
**Created:** 2026-02-23
**Source:** 6 pre-release audits (concurrency, memory, SwiftUI performance, SwiftUI architecture, storage, accessibility)
**Total raw issues:** 60
**Already fixed:** 2 (CONC-C1: FileMetadataRepository Sendable, STOR-C1: stopAccessingSecurityScopedResource)
**Resolved by other fix:** 1 (CONC-H5: Sendable propagation → resolved by CONC-C1)
**No action needed:** 3 (ARCH-L2: Coordinator complexity is expected, ARCH-L3: ChatView tasks already well-handled, ARCH-L4: MainActor.assumeIsolated is correct pattern)
**Remaining fixes:** 54 across 16 user stories

---

## Phase 1: Infrastructure & Storage (HIGH risk)

### US-1: Fix FolderService.swift

**File:** `Sources/Services/FolderService.swift`
**Audit refs:** CONC-H3, CONC-H4, PERF-M3, STOR-H2, MEM-M4
**Changes:** 5

1. **CONC-H3** (line ~37): Replace `Task.detached(priority: .utility) { [weak self] in await self?.loadCacheFromDisk() }` with `Task { await loadCacheFromDisk() }`. The non-detached Task inherits @MainActor from init context — no weak self needed.

2. **CONC-H4** (line ~72): Add `[weak self]` to `cacheSaveTask = Task { ... }` closure. Change `saveCacheToDisk()` to `self?.saveCacheToDisk()`.

3. **PERF-M3** (line ~79): Move encode+write in `saveCacheToDisk()` off the main thread. Capture `cache` snapshot on main, then `Task.detached(priority: .utility)` for JSONEncoder + data.write.

4. **STOR-H2** (line ~87-93): Move `isExcludedFromBackup` resource value setting BEFORE the `data.write(to:)` call to prevent race condition where file gets backed up before exclusion is set.

5. **MEM-M4**: Add `func flushCacheIfNeeded()` public method that cancels cacheSaveTask and calls saveCacheToDisk synchronously. Called from AppDelegate on termination (wired in US-8).

**Acceptance Criteria:**
- [ ] `init()` uses `Task { }` not `Task.detached`
- [ ] `scheduleCacheSave` closure has `[weak self]`
- [ ] `saveCacheToDisk` runs JSONEncoder + write in `Task.detached`
- [ ] `isExcludedFromBackup` set before `data.write(to:)`
- [ ] `flushCacheIfNeeded()` method exists and is public

---

### US-2: Fix SwiftDataMetadataRepository.swift

**File:** `Sources/Persistence/SwiftDataMetadataRepository.swift`
**Audit refs:** CONC-H2, STOR-H4
**Changes:** 2

1. **CONC-H2** (line ~160): Change `nonisolated(unsafe) public static var versionIdentifier = Schema.Version(1, 0, 0)` to `public static let versionIdentifier = Schema.Version(1, 0, 0)`. Remove `nonisolated(unsafe)` — a `let` is implicitly Sendable.

2. **STOR-H4** (line ~190-199): Add `fileProtection: .complete` to `ModelConfiguration` in `makeContainer()`.

**Acceptance Criteria:**
- [ ] `SchemaV1.versionIdentifier` is `static let` with no `nonisolated(unsafe)`
- [ ] `ModelConfiguration` includes `fileProtection: .complete`

---

### US-3: Migrate SecurityScopedBookmarkManager to File Storage

**File:** `Sources/Services/SecurityScopedBookmarkManager.swift`
**Audit refs:** STOR-H1, STOR-M2
**Changes:** 3 (including migration)

1. **STOR-H1**: Migrate bookmark data from `UserDefaults.standard.set(bookmarkData, forKey: key)` to file-based storage in `~/Library/Application Support/AIMDReader/Bookmarks/{key}.bookmark` with `.completeFileProtection`. Add migration path: on first access, check UserDefaults for existing data, migrate to file, then remove from UserDefaults.

2. **STOR-M2**: Replace `print("Warning: Failed to save bookmark...")` with `os.log` Logger. Add `private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aimd.reader", category: "BookmarkManager")`.

3. **Migration**: On `resolveBookmark(for:)`, if no file exists, check UserDefaults for legacy data. If found, write to file storage and remove from UserDefaults. Transparent to callers.

**Acceptance Criteria:**
- [ ] Bookmark data stored as files in Application Support, not UserDefaults
- [ ] `.completeFileProtection` option used on write
- [ ] Legacy UserDefaults bookmarks migrated on first access
- [ ] All `print()` replaced with `Logger.error()` / `Logger.warning()`
- [ ] UserDefaults key removed after successful migration

---

### US-4: Migrate RecentFoldersManager to File Storage

**File:** `Sources/Services/RecentFoldersManager.swift`
**Audit refs:** STOR-H3, STOR-M1
**Changes:** 3 (including migration)

1. **STOR-H3**: Migrate recent folders and recent files from UserDefaults to file-based storage in `~/Library/Application Support/AIMDReader/RecentFolders.json` and `RecentFiles.json` with `.completeFileProtection` and `isExcludedFromBackup = true`.

2. **STOR-M1**: Replace `try?` silent decoding with proper `do/catch` that logs errors via `os.log` Logger. On decode failure, log the error and clear corrupted data.

3. **Migration**: On `getRecentFolders()` / `getRecentFiles()`, if no file exists, check UserDefaults for legacy data. If found, write to file, remove from UserDefaults.

**Acceptance Criteria:**
- [ ] Recent folders/files stored as JSON files in Application Support
- [ ] `.completeFileProtection` on writes
- [ ] `isExcludedFromBackup = true` set before write
- [ ] JSON decode errors logged with os.log, not silently swallowed
- [ ] Legacy UserDefaults data migrated on first access

---

## Phase 2: AppKit Bridging & Memory

### US-5: Fix MarkdownEditor.swift

**File:** `Sources/MarkdownEditor.swift`
**Audit refs:** CONC-H1, MEM-H2, MEM-M5, ACC-M3, PERF-L1
**Changes:** 4

1. **CONC-H1** (line ~285): Replace `DispatchQueue.main.async { ... }` in `restoreScrollPosition` with `Task { @MainActor in ... }`.

2. **MEM-H2 + MEM-M5**: Add `static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator)` that:
   - Sets `textView.delegate = nil`
   - Calls `NotificationCenter.default.removeObserver(coordinator)`
   This provides deterministic cleanup instead of relying on `deinit`.

3. **ACC-M3** (in `makeNSView`): Add NSTextView accessibility attributes:
   ```swift
   textView.setAccessibilityElement(true)
   textView.setAccessibilityLabel("Markdown document viewer")
   textView.setAccessibilityRole(.textArea)
   textView.setAccessibilityHelp("Read-only markdown content with syntax highlighting. Use Cmd+F to search.")
   ```

4. **PERF-L1** (line ~220): For initial file load (non-debounced path), offload `highlighter.highlight(text)` to `Task.detached(priority: .userInitiated)` with `MainActor.run` completion to set attributed string. Preserves selected ranges.

**Acceptance Criteria:**
- [ ] No `DispatchQueue.main.async` in file
- [ ] `dismantleNSView` exists and nils delegate + removes observer
- [ ] NSTextView has accessibilityLabel "Markdown document viewer"
- [ ] Initial highlighting for files > 50KB runs off main thread

---

### US-6: Fix OutlineFileList.swift

**File:** `Sources/Views/Components/OutlineFileList.swift`
**Audit refs:** PERF-H3, MEM-M3, ACC-M5, ACC-M6
**Changes:** 4

1. **PERF-H3** (line ~230): Pre-fetch all favorites as `Set<String>` before `reloadData()`. Store as `coordinator.favoritePathsSet`. In `outlineView(_:viewFor:item:)`, use `favoritePathsSet.contains(folderItem.url.path)` instead of per-row `isFavorite?(folderItem.url)`.

2. **MEM-M3**: Add `static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator)` that sets `outlineView.dataSource = nil` and `outlineView.delegate = nil`.

3. **ACC-M5** (in `makeNSView`): Add accessibility hints to NSOutlineView:
   ```swift
   outlineView.setAccessibilityLabel("File browser")
   outlineView.setAccessibilityHelp("Use arrow keys to navigate, left/right to expand/collapse folders, Return to select file")
   ```

4. **ACC-M6**: In `FileCellView.configure`, set accessibility attributes:
   - `.setAccessibilityLabel()` with file name + type ("Folder: Models" or "File: README.md")
   - Include favorite status in label when applicable ("File: README.md, favorited")

**Acceptance Criteria:**
- [ ] `reloadData()` preceded by `getFavorites()` → `Set<String>` assignment
- [ ] No per-row `isFavorite?()` calls during cell configuration
- [ ] `dismantleNSView` exists and nils dataSource + delegate
- [ ] NSOutlineView has accessibilityLabel "File browser"
- [ ] FileCellView announces file type and favorite status to VoiceOver

---

### US-7: Fix MarkdownView.swift

**File:** `Sources/Views/Screens/MarkdownView.swift`
**Audit refs:** MEM-H1, PERF-M1, PERF-M2
**Changes:** 3

1. **MEM-H1** (line ~180): Change `FileWatcher { [coordinator] in coordinator.markDocumentChanged() }` to `FileWatcher { [weak coordinator] in coordinator?.markDocumentChanged() }`.

2. **PERF-M1** (line ~163): In `toggleBookmark`, after the add/delete operation, fetch bookmarks once and assign directly to `bookmarkedLines` instead of calling `refreshBookmarks()` which does a second identical fetch.

3. **PERF-M2** (line ~216): Replace `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` computed property with `@Environment(\.accessibilityReduceMotion) private var reduceMotion`.

**Acceptance Criteria:**
- [ ] FileWatcher closure uses `[weak coordinator]` and optional chaining
- [ ] `toggleBookmark` does exactly 2 SwiftData fetches (getBookmarks + getBookmarks), not 3
- [ ] Uses `@Environment(\.accessibilityReduceMotion)` not `NSWorkspace`

---

## Phase 3: App-Level Fixes

### US-8: Fix AIMDReaderApp.swift

**File:** `Sources/AIMDReaderApp.swift`
**Audit refs:** CONC-M1, CONC-M2, MEM-L6, MEM-M4 (termination)
**Changes:** 3

1. **CONC-M1** (line ~308): Add `@MainActor` annotation to `panel.begin` completion closure: `panel.begin { @MainActor response in ... }`.

2. **CONC-M2 + MEM-L6** (lines ~66-77): Simplify AppDelegate's `openMarkdownFileWithFolderAccess` panel completion. Replace `Task { @MainActor in ... }` wrapper with `@MainActor` annotation on the closure itself. Add `[weak self]` alongside existing `[weak coordinator]`.

3. **MEM-M4 (termination)**: Add `applicationWillTerminate(_ notification: Notification)` to AppDelegate that calls `FolderService.shared.flushCacheIfNeeded()`.

**Acceptance Criteria:**
- [ ] All `panel.begin` closures annotated with `@MainActor`
- [ ] No `Task { @MainActor in }` wrapper in AppDelegate panel completion
- [ ] `[weak self]` in AppDelegate panel completion
- [ ] `applicationWillTerminate` calls `FolderService.shared.flushCacheIfNeeded()`

---

### US-9: Fix ContentView.swift

**File:** `Sources/ContentView.swift`
**Audit refs:** PERF-H1, PERF-H2, ACC-H1, ACC-H2, ACC-L1
**Changes:** 5

1. **PERF-H1** (line ~92): Cache the `FolderTreeFilter.flattenMarkdownFiles()` result. Add `@State private var allMarkdownFiles: [FolderItem] = []` and recompute in `.onChange(of: coordinator.navigation.displayItems)` instead of calling inline in body. Pass cached array to `.quickSwitcherOverlay(allFiles:)`.

2. **PERF-H2** (line ~266): Change `.onChange(of: coordinator.navigation.displayItems.count)` to `.onChange(of: coordinator.navigation.displayItems)`. FolderItem is Hashable so SwiftUI's value equality diffing works correctly.

3. **ACC-H1** (lines ~196-202): Add `.accessibilityLabel("Clear sidebar filter")` and `.accessibilityHint("Removes the current filter to show all files")` to clear filter button.

4. **ACC-H2** (lines ~207-215): Add dynamic `.accessibilityLabel(showFavoritesOnly ? "Show all files" : "Show favorites only")` to favorites toggle button.

5. **ACC-L1** (multiple lines): For buttons that already have `.help()`, add corresponding `.accessibilityLabel()` and `.accessibilityHint()`. `.help()` is for hover tooltips only — VoiceOver uses `.accessibilityLabel`.

**Acceptance Criteria:**
- [ ] `flattenMarkdownFiles` called in `.onChange`, not in body
- [ ] `allMarkdownFiles` is a `@State` property
- [ ] `.onChange` observes full `displayItems` array, not `.count`
- [ ] Clear filter button reads "Clear sidebar filter" in VoiceOver
- [ ] Favorites toggle reads current state in VoiceOver
- [ ] All icon-only buttons have `.accessibilityLabel`

---

### US-10: Fix QuickSwitcher.swift

**File:** `Sources/Views/Components/QuickSwitcher.swift`
**Audit refs:** ARCH-M1, PERF-M4, ARCH-L6, ACC-M2, ACC-M1
**Changes:** 4

1. **ARCH-M1** (lines ~16-39): Extract search scoring logic from `private var results` computed property to a standalone function (either a `static func` on QuickSwitcher or a `URL` extension / free function). The view's `results` property calls the extracted function.

2. **PERF-M4 + ARCH-L6** (lines ~138-154): Pre-compute `parentPath` in the caller when building results. Change `QuickSwitcherRow` to accept `parentPath: String` as a parameter instead of computing it from `rootURL` on every body evaluation. Extract the path computation to a `URL.relativeParentPath(from:)` extension.

3. **ACC-M2** (lines ~102-117): Add `.accessibilityValue("Result \(index + 1) of \(results.count)")` to each QuickSwitcherRow for VoiceOver navigation context.

4. **ACC-M1**: Add comment documenting the fixed width: `// Fixed width: 500pt chosen for optimal quick-switcher reading width. macOS handles zoom at OS level.`

**Acceptance Criteria:**
- [ ] Search scoring logic is in a separate function, not inline in view
- [ ] `QuickSwitcherRow` receives `parentPath: String` as parameter
- [ ] Each row announces "Result X of Y" to VoiceOver
- [ ] Width design choice documented in comment

---

## Phase 4: Accessibility & Chat

### US-11: Fix ChatView.swift

**File:** `Sources/Views/Screens/ChatView.swift`
**Audit refs:** ACC-H3, ACC-H4, ACC-L3
**Changes:** 3

1. **ACC-H3** (lines ~268-276): Add `.accessibilityLabel("Send message")` to the send button (arrow.up.circle.fill icon).

2. **ACC-H4** (lines ~82-88): Add `.accessibilityLabel("Clear conversation history")` to the "Forget" button. Keep existing `.help()` for hover tooltip.

3. **ACC-L3** (lines ~385-418): Add `.accessibilityValue(message.role == .user ? "Your message" : "Assistant response")` to MessageBubble for VoiceOver sender identification.

**Acceptance Criteria:**
- [ ] Send button reads "Send message" in VoiceOver
- [ ] Forget button reads "Clear conversation history" in VoiceOver
- [ ] Message bubbles announce sender role in VoiceOver

---

### US-12: Fix ChatService.swift

**File:** `Sources/Services/ChatService.swift`
**Audit refs:** CONC-M3, ARCH-M5
**Changes:** 2

1. **CONC-M3** (line ~110): Extract session reference to local variable before Task creation as a defensive measure against potential future Sendable enforcement:
   ```swift
   guard let session else { return .error("Session could not be created.") }
   let capturedSession = session
   let respondTask = Task<String, Error> {
       let response = try await capturedSession.respond(to: question)
       return response.content
   }
   ```

2. **ARCH-M5** (lines ~86-148): Add State-as-Bridge pattern documentation comment to `askAI` in ChatView.swift (the calling site), explaining: (1) synchronous state mutation before await, (2) async boundary delegated to service, (3) synchronous state update after await.

**Acceptance Criteria:**
- [ ] `session` captured to local `let capturedSession` before Task creation
- [ ] State-as-Bridge pattern documented with inline comment at call site

---

### US-13: Fix StartView.swift

**File:** `Sources/Views/Screens/StartView.swift`
**Audit refs:** CONC-M1, PERF-M2, ACC-M1
**Changes:** 3

1. **CONC-M1** (line ~197): Add `@MainActor` annotation to `panel.begin` completion closure.

2. **PERF-M2** (line ~383): Replace `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in `MascotButtonStyle` with `@Environment(\.accessibilityReduceMotion) private var reduceMotion`.

3. **ACC-M1**: Add comment documenting fixed frame design choice: `// Fixed 480x520: Welcome window sized for visual balance. macOS handles zoom at OS level.`

**Acceptance Criteria:**
- [ ] `panel.begin` closure annotated with `@MainActor`
- [ ] MascotButtonStyle uses `@Environment(\.accessibilityReduceMotion)` not `NSWorkspace`
- [ ] Frame design choice documented in comment

---

## Phase 5: Polish & Documentation

### US-14: Fix Settings & UI Polish Files

**Files:** `Sources/Views/Screens/SettingsView.swift`, `Sources/Settings/SettingsRepository.swift`, `Sources/Views/Components/ErrorBanner.swift`
**Audit refs:** ACC-M7, ACC-L2, ACC-M1, CONC-L1, ARCH-M2, ARCH-M4, PERF-M2, ARCH-L7
**Changes:** 6

1. **SettingsView — ACC-M7** (lines ~161, 166): Increase theme indicator circles from `.frame(width: 10, height: 10)` to `.frame(width: 16, height: 16)` for better target size.

2. **SettingsView — ACC-L2** (lines ~153-168): Add text label alongside color circle for theme indicators so users with color blindness can distinguish themes.

3. **SettingsView — ACC-M1**: Add comment documenting fixed frame design choice.

4. **SettingsRepository — CONC-L1** (line ~314): Add comment explaining `@preconcurrency` on EnvironmentKey: `// @preconcurrency required: EnvironmentKey.defaultValue lacks @MainActor annotation. Safe because SwiftUI accesses this on @MainActor view update path.`

5. **SettingsRepository — ARCH-M2 + ARCH-M4**: Add advisory TODO comment noting potential future decomposition of the aggregated settings repository and SwiftUI import coupling.

6. **ErrorBanner — PERF-M2 + ARCH-L7**: Replace `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` with `@Environment(\.accessibilityReduceMotion)`. Extract hardcoded `Task.sleep(for: .seconds(5))` to a `private let errorDismissTimeout: Duration = .seconds(5)` constant.

**Acceptance Criteria:**
- [ ] Theme indicator circles are 16x16pt minimum
- [ ] Theme indicators include text label alongside color
- [ ] `@preconcurrency` usage documented with explanatory comment
- [ ] ErrorBanner uses `@Environment(\.accessibilityReduceMotion)`
- [ ] Error dismiss timeout extracted to named constant

---

### US-15: Fix Model & Documentation Files

**Files:** `Sources/Models/FolderItem.swift`, `Sources/Coordinator/AppCoordinator.swift`, `Sources/Views/Components/LineNumberRulerView.swift`, `Sources/Services/WelcomeManager.swift`, `Sources/Services/FolderTreeFilter.swift`
**Audit refs:** CONC-L2, CONC-L1, ACC-M4, STOR-L1, PERF-M5
**Changes:** 5

1. **FolderItem — CONC-L2**: Add explicit `: Sendable` conformance to `FolderItem` struct. Verifies at compile time that all stored properties are Sendable.

2. **AppCoordinator — CONC-L1** (line ~419): Add comment explaining `@preconcurrency` on `AppCoordinatorKey: EnvironmentKey` conformance (same pattern as SettingsRepository).

3. **LineNumberRulerView — ACC-M4**: Mark as non-accessible/decorative by overriding `accessibilityElement` to return `NSNumber(value: false)`. Line numbers are visual decoration — VoiceOver should skip them.

4. **WelcomeManager — STOR-L1**: Add documentation comment explaining the Welcome folder location choice (`~/Library/Application Support/AIMDReader/Welcome` — persists, backed up, hidden from user).

5. **FolderTreeFilter — PERF-M5** (line ~9): Fix fragile cache key. Add `rootPath: String` parameter to `filterByName()` and include it in the cache key tuple alongside `itemCount` and `query`. Prevents stale results when switching between folders with the same file count.

**Acceptance Criteria:**
- [ ] `FolderItem` declares `: Sendable`
- [ ] Both `@preconcurrency` EnvironmentKey usages documented
- [ ] LineNumberRulerView returns `false` for `accessibilityElement`
- [ ] WelcomeManager has documentation comment explaining storage location
- [ ] `filterByName` cache key includes root path

---

## Phase 6: Build Verification

### US-16: Full Build Verification

**Changes:** 1 (environment + build)

1. Switch `xcode-select` to `/Applications/Xcode.app/Contents/Developer`
2. Run `xcodebuild build -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS'`
3. Verify build succeeds with zero errors
4. Review any new warnings introduced by the fixes

**Acceptance Criteria:**
- [ ] `xcode-select -p` returns Xcode.app path
- [ ] `xcodebuild build` exits with code 0
- [ ] No new warnings introduced by audit fixes

---

## Summary

| Phase | Stories | Changes | Risk Level |
|-------|---------|---------|------------|
| 1: Infrastructure & Storage | US-1 through US-4 | 13 | HIGH |
| 2: AppKit Bridging & Memory | US-5 through US-7 | 11 | HIGH |
| 3: App-Level Fixes | US-8 through US-10 | 12 | MEDIUM |
| 4: Accessibility & Chat | US-11 through US-13 | 8 | MEDIUM |
| 5: Polish & Documentation | US-14, US-15 | 11 | LOW |
| 6: Build Verification | US-16 | 1 | — |
| **Total** | **16 stories** | **56 changes** | |

## Excluded (No Action Needed)

| Issue | Reason |
|-------|--------|
| CONC-C1 | Already fixed (removed `: Sendable`) |
| STOR-C1 | Already fixed (added `defer { stopAccessingSecurityScopedResource() }`) |
| CONC-H5 | Resolved by CONC-C1 fix |
| ARCH-L2 | OutlineFileList coordinator complexity is expected for NSViewRepresentable |
| ARCH-L3 | ChatView task management already correct with onDisappear cleanup |
| ARCH-L4 | MainActor.assumeIsolated is correct pattern for AppKit delegate callbacks |

## Audit Reports

Full detailed reports available in:
- `scratch/audit-concurrency-2026-02-23.md`
- `scratch/audit-memory-2026-02-23.md`
- `scratch/audit-swiftui-performance-2026-02-23.md`
- `scratch/audit-swiftui-architecture-2026-02-23.md`
- `scratch/audit-storage-2026-02-23.md`
- `scratch/audit-accessibility-2026-02-23.md`

## Implementation Notes

### Overlapping Fixes (merged into single story)
- MEM-H2 + MEM-M5 → single `dismantleNSView` for MarkdownEditor (US-5)
- CONC-M2 + MEM-L6 → single fix for AppDelegate NSOpenPanel closure (US-8)
- PERF-M4 + ARCH-L6 → single fix to extract parentPath (US-10)
- PERF-M2 appears in US-7, US-13, US-14 (3 files use NSWorkspace reduce motion)

### Storage Migration Strategy
US-3 and US-4 introduce file-based storage with transparent migration. On first access after update:
1. Check for new file storage location
2. If missing, check UserDefaults for legacy data
3. If found, write to file storage with protection
4. Remove legacy UserDefaults key
5. Subsequent accesses use file storage only

### Risk Notes
- US-3/US-4 storage migration must handle the case where migration succeeds for write but UserDefaults removal fails (idempotent — re-migration is safe since file exists)
- US-5 async highlighting (PERF-L1) must preserve cursor position and avoid flicker
- US-9 displayItems diffing change (PERF-H2) depends on FolderItem being Equatable/Hashable — verify
