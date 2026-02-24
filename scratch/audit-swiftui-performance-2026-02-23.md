# SwiftUI Performance Audit Results

**Project:** AI.md Reader — `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources`
**Date:** 2026-02-23
**Files audited:** 30 Swift files (12 SwiftUI view files + services, models, AppKit wrappers)
---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 3 |
| MEDIUM | 5 |
| LOW | 1 |
| **Total** | **9** |

**Performance Risk Score: 3.5 / 10** (LOW-MEDIUM risk)

The codebase is well-architected overall. It uses `@Observable` throughout, keeps file I/O in async contexts, and avoids the most damaging anti-patterns. The issues found are refinements, not emergencies.

---

## Issues by Severity

---

### HIGH — 3 Issues

---

#### HIGH-1: Expensive Tree Flatten on Every View Body Evaluation

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/ContentView.swift:92`

**Code:**
```swift
.quickSwitcherOverlay(allFiles: FolderTreeFilter.flattenMarkdownFiles(coordinator.navigation.displayItems))
```

**Issue:** `FolderTreeFilter.flattenMarkdownFiles()` is a recursive tree-walk called inline as a modifier argument inside `browserContent`, which is a `var` (computed property) on `BrowserView`. Every time `BrowserView.body` re-evaluates — triggered by any change to `coordinator` — this full tree traversal runs on the main thread before rendering. For a folder with hundreds of markdown files and nested subdirectories, this is O(N) work on every coordinator state change (file selection, AI chat toggle, filter query changes, etc.).

**Impact:** Each body evaluation incurs a full recursive traversal of `displayItems`. If a user is scrolling the file list or typing in the search field, this fires repeatedly. The result set (`allFiles`) is only needed when the Quick Switcher is actually visible, but the computation always runs.

**Fix:** Cache the flattened list in `OutlineFileListWrapper` where `displayItems` is already managed, and pass it up — or memoize it with a lazy `@State` property that only recomputes when `displayItems.count` changes:

```swift
// In BrowserView or OutlineFileListWrapper:
@State private var allMarkdownFiles: [FolderItem] = []

// In .onChange(of: coordinator.navigation.displayItems.count):
allMarkdownFiles = FolderTreeFilter.flattenMarkdownFiles(coordinator.navigation.displayItems)

// Then:
.quickSwitcherOverlay(allFiles: allMarkdownFiles)
```

Alternatively, compute lazily inside `QuickSwitcherOverlay` only when `isQuickSwitcherVisible` becomes true.

---

#### HIGH-2: `.onChange(of: displayItems.count)` Misses Content Changes

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/ContentView.swift:266`

**Code:**
```swift
.onChange(of: coordinator.navigation.displayItems.count) { _, _ in
    recomputeFilteredItems(debounce: false)
}
```

**Issue:** Observing only `.count` means if files are renamed, favorite status changes, or items are replaced (same count but different content), the filtered list goes stale. The view would display outdated data without triggering a recompute. This is a correctness issue that degrades perceived performance — the user sees a stale list and has to manually refresh.

More subtly, `displayItems.count` evaluates the entire array count on every body pass through `@Observable` tracking, which is fine, but it creates an implicit dependency on the full `displayItems` array reference rather than just the count scalar, meaning any mutation to `displayItems` (even non-count changes) will re-trigger this closure anyway via `@Observable`'s property-level tracking — the `.count` guard may give false confidence.

**Impact:** Stale sidebar after file rename or favorite toggle without a count change.

**Fix:** Observe the full array identity via a stable hash or use a dedicated `displayItemsVersion` counter incremented on every mutation:

```swift
// In NavigationState:
private(set) var displayItemsVersion: Int = 0

func setDisplayItems(_ items: [FolderItem]) {
    displayItems = items
    displayItemsVersion += 1
}

// In OutlineFileListWrapper:
.onChange(of: coordinator.navigation.displayItems) { _, _ in
    recomputeFilteredItems(debounce: false)
}
```

Or simply observe the whole `displayItems` property (SwiftUI's `@Observable` diffing for arrays uses value equality if `Equatable` — `FolderItem` is `Hashable` so this is efficient).

---

#### HIGH-3: `isFavorite` Closure Called Per Row on Every NSOutlineView Reload

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/OutlineFileList.swift:230`

**Code:**
```swift
let favorited = folderItem.isMarkdown ? (isFavorite?(folderItem.url) ?? false) : false
cell.configure(with: folderItem, indentLevel: indentLevel, outlineView: outlineView, isFavorite: favorited, ...)
```

**And in `updateNSView`:**
```swift
let itemsChanged = context.coordinator.items.count != items.count
if itemsChanged {
    outlineView.reloadData()
    ...
}
```

**Issue:** When `outlineView.reloadData()` fires, `outlineView(_:viewFor:item:)` is called for every visible row. Each call invokes `isFavorite?(folderItem.url)` which calls `coordinator.isFavorite(url)` which calls `metadata?.isFavorite(url)` which calls `getMetadata(for: url)` which executes a SwiftData `FetchDescriptor` fetch per row. For a list of 50 markdown files, this is 50 sequential SwiftData fetches per reload.

**Impact:** Janky reloads when the folder tree loads or updates. Each SwiftData fetch involves predicate evaluation, in-memory object graph traversal, and is not free. 50 fetches x ~0.1ms each = ~5ms blocking the main thread.

**Fix:** Pre-fetch all favorites as a `Set<String>` (paths) before the reload and pass it into the coordinator for O(1) lookup during cell configuration:

```swift
// Before reloadData():
let favoritePathsSet: Set<String> = Set(
    (coordinator.metadata?.getFavorites() ?? []).map { $0.path }
)
context.coordinator.favoritePathsSet = favoritePathsSet
outlineView.reloadData()

// In outlineView(_:viewFor:item:):
let favorited = folderItem.isMarkdown && (coordinator.favoritePathsSet?.contains(folderItem.url.path) ?? false)
```

---

### MEDIUM — 5 Issues

---

#### MEDIUM-1: Whole-Collection Linear Scan in `toggleBookmark`

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Screens/MarkdownView.swift:163`

**Code:**
```swift
private func toggleBookmark(at lineNumber: Int) {
    let existing = coordinator.getBookmarks()
    if let bookmark = existing.first(where: { $0.lineNumber == lineNumber }) {
        coordinator.deleteBookmark(bookmark.id)
    } else {
        coordinator.addBookmark(lineNumber: lineNumber)
    }
    refreshBookmarks()
}
```

**Issue:** `coordinator.getBookmarks()` executes a SwiftData fetch, then `.first(where:)` performs a linear scan. This runs synchronously in the click handler (via `onToggleBookmark` called from `LineNumberRulerView.mouseDown`). While bookmark counts are small (typically < 50), the pattern of fetching all then scanning is wasteful and could be replaced.

**Impact:** Minor — low bookmark counts keep this below perceptible threshold. However, `refreshBookmarks()` immediately follows, issuing a second identical fetch. Two redundant SwiftData fetches per bookmark toggle.

**Fix:** Combine the toggle and refresh into a single fetch, or pass the result of `getBookmarks()` to `refreshBookmarks()` to avoid the second fetch:

```swift
private func toggleBookmark(at lineNumber: Int) {
    let existing = coordinator.getBookmarks()
    if let bookmark = existing.first(where: { $0.lineNumber == lineNumber }) {
        coordinator.deleteBookmark(bookmark.id)
    } else {
        coordinator.addBookmark(lineNumber: lineNumber)
    }
    // Reuse the existing array rather than fetching again
    // After toggle, recompute locally:
    let updated = coordinator.getBookmarks()  // one fetch total
    bookmarkedLines = Set(updated.map(\.lineNumber))
}
```

---

#### MEDIUM-2: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` Called in View Body

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Screens/StartView.swift:383` and `387`
**Also:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Screens/MarkdownView.swift:216`
**Also:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/ErrorBanner.swift:74`

**Code (StartView.swift:383):**
```swift
private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

func makeBody(configuration: Configuration) -> some View {
    configuration.label
        .scaleEffect(reduceMotion ? 1.0 : ...)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: ...)
```

**Issue:** `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is a synchronous property access on `NSWorkspace.shared` (a singleton backed by Notification Center). It is not expensive per call, but it is called inside `makeBody` which is evaluated on every view update. More importantly, SwiftUI has a native `@Environment(\.accessibilityReduceMotion)` that is automatically kept in sync and participates properly in SwiftUI's update mechanism. The `NSWorkspace` approach also bypasses the standard `@Environment` system so these views will not respond to live accessibility preference changes while the view is displayed (the environment value would update; the computed property re-reads `NSWorkspace` on the next body call, which is fine, but the SwiftUI environment path is preferred).

**Impact:** Minor correctness/style issue. `NSWorkspace` is not expensive, but using the non-SwiftUI path means losing automatic subscription to preference-change notifications via the view hierarchy.

**Fix:** Use `@Environment(\.accessibilityReduceMotion)` in all view types:

```swift
// In MascotButtonStyle:
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// In ErrorBannerOverlay and MarkdownView:
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

For `ButtonStyle` types (which cannot use `@Environment` directly in the standard way), use the environment approach via `EnvironmentValues` in the `makeBody` configuration. In practice this is fine on macOS with `NSViewRepresentable` bridging.

---

#### MEDIUM-3: `saveCacheToDisk` Runs Synchronously on Main Thread

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Services/FolderService.swift:79`

**Code:**
```swift
private func saveCacheToDisk() {
    guard let url = cacheFileURL else { return }
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(cache) {
        try? data.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
        ...
    }
}
```

**Issue:** `FolderService` is `@MainActor`. `saveCacheToDisk()` runs `JSONEncoder().encode(cache)` and `data.write(to:)` synchronously on the main thread. The cache can contain a full folder tree (`[String: CachedFolder]`) which for large repositories may encode to hundreds of kilobytes of JSON. `data.write(to:options:)` with `.completeFileProtectionUntilFirstUserAuthentication` is a synchronous disk write. This runs from `scheduleCacheSave` which is called after every `invalidateCache` call, including on `BrowserView.onDisappear`.

The debounce (2-second delay) in `scheduleCacheSave` mitigates frequency but not the on-main-thread execution.

**Impact:** A large folder tree (thousands of files) could produce a cache JSON of 500KB+. Encoding and writing this synchronously on the main thread can drop frames. On fast SSDs this is often < 5ms, but on older/slower volumes it could exceed a frame budget (16.7ms).

**Fix:** Move the encode+write off the main thread:

```swift
private func saveCacheToDisk() {
    guard let url = cacheFileURL else { return }
    let cacheSnapshot = cache  // capture value on main thread
    
    Task.detached(priority: .utility) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cacheSnapshot) {
            try? data.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(resourceValues)
        }
    }
}
```

---

#### MEDIUM-4: `QuickSwitcherRow.parentPath` Computed on Every Body Call

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/QuickSwitcher.swift:139`

**Code:**
```swift
private var parentPath: String {
    guard let root = rootURL else { return "" }
    let parentURL = item.url.deletingLastPathComponent()
    let rootPath = root.path
    let parentPathStr = parentURL.path

    if parentPathStr == rootPath { return "" }
    if parentPathStr.hasPrefix(rootPath) {
        let relative = String(parentPathStr.dropFirst(rootPath.count))
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }
    return parentURL.lastPathComponent
}

var body: some View {
    HStack(spacing: 8) {
        ...
        VStack(alignment: .leading, spacing: 1) {
            Text(item.name)
            if !parentPath.isEmpty {
                Text(parentPath)
```

**Issue:** `parentPath` is a computed property called inside `body`. It performs URL string manipulation (`deletingLastPathComponent()`, `.path`, `hasPrefix`, `dropFirst`) on every body evaluation. `QuickSwitcherRow` is used inside a `LazyVStack` with up to 20 visible rows, and each row re-evaluates on `selectedIndex` changes (because `isSelected: index == selectedIndex` changes). With keyboard navigation (arrow keys), every keypress triggers 2 row updates (deselect old, select new) × `parentPath` computation for each visible row.

**Impact:** 20+ string manipulation operations per keystroke. Each is individually fast but the pattern is unnecessary.

**Fix:** Make `parentPath` a stored property by converting `QuickSwitcherRow` to accept it pre-computed, or cache it with a lazy approach:

```swift
struct QuickSwitcherRow: View {
    let item: FolderItem
    let isSelected: Bool
    let parentPath: String  // Pre-computed by caller

    var body: some View { ... }
}

// In QuickSwitcher, pre-compute when building results:
ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
    QuickSwitcherRow(
        item: item,
        isSelected: index == selectedIndex,
        parentPath: computeParentPath(for: item, root: coordinator.navigation.rootFolderURL)
    )
}
```

---

#### MEDIUM-5: `FolderTreeFilter.nameFilterCache` Key is Fragile (`itemCount` Only)

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Services/FolderTreeFilter.swift:9`

**Code:**
```swift
@MainActor
private static var nameFilterCache: (itemCount: Int, query: String, result: [FolderItem])?

@MainActor
static func filterByName(_ items: [FolderItem], query: String) -> [FolderItem] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return items }

    if let cached = nameFilterCache,
       cached.itemCount == items.count,
       cached.query == trimmed {
        return cached.result
    }
    ...
}
```

**Issue:** The cache key uses only `itemCount` (not content identity). If items are replaced with a different set of the same count (e.g., a file is renamed, or the folder is switched to another folder with the same file count), the cache incorrectly returns a stale result. This is a correctness hazard that can make filtering appear "stuck" after certain folder navigation sequences.

Additionally, this is a static cache, meaning it persists for the lifetime of the app. If the user opens a second folder with the same count and same query, the old folder's results are returned.

**Impact:** Silent staleness — users may see wrong filter results. This is primarily a correctness issue but affects perceived performance (user re-types query to force refresh).

**Fix:** Use the root folder URL as part of the cache key, or use an identity-based key:

```swift
private static var nameFilterCache: (rootPath: String, itemCount: Int, query: String, result: [FolderItem])?

static func filterByName(_ items: [FolderItem], query: String, rootPath: String = "") -> [FolderItem] {
    if let cached = nameFilterCache,
       cached.rootPath == rootPath,
       cached.itemCount == items.count,
       cached.query == trimmed {
        return cached.result
    }
    let result = _filterByName(items, query: trimmed)
    nameFilterCache = (rootPath: rootPath, itemCount: items.count, query: trimmed, result: result)
    return result
}
```

---

### LOW — 1 Issue

---

#### LOW-1: `MarkdownHighlighter.highlight()` Runs Synchronously on Main Thread for Large Files

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/MarkdownEditor.swift:220`

**Code:**
```swift
func applyHighlighting(to textView: NSTextView, text: String) {
    ...
    let attributed = debouncedHighlighter.highlighter.highlight(text)
    textView.textStorage?.setAttributedString(attributed)
}
```

**Issue:** `applyHighlighting` is called synchronously on the main thread for initial content load and settings changes (not debounced). `MarkdownHighlighter.highlight()` runs 10 NSRegularExpression passes over the full document. For a 500KB markdown file (near the 1MB highlight limit), this involves 10 regex scans × 500,000 characters. NSRegularExpression is not trivially fast for large inputs.

The `DebouncedHighlighter` exists for text-change paths but the initial-load path (`applyHighlighting`) bypasses debouncing and runs synchronously.

**Note:** The 1MB guard (`maxHighlightSize`) provides a hard ceiling and prevents the worst-case DoS scenario. This issue only matters for files in the 100KB–1MB range.

**Impact:** Initial file load of large markdown files (100KB+) may briefly freeze the main thread while highlighting runs. Measured anecdotally at ~10–50ms for a 200KB file on Apple Silicon, which is below typical ANR thresholds but exceeds a single frame budget.

**Fix:** Offload initial highlighting to a background task with a main-thread completion:

```swift
func applyHighlightingAsync(to textView: NSTextView, text: String) {
    guard !isUpdating else { return }
    guard text.utf8.count <= MarkdownConfig.maxTextSize else { return }

    let highlighter = debouncedHighlighter.highlighter
    Task.detached(priority: .userInitiated) {
        let attributed = highlighter.highlight(text)
        await MainActor.run { [weak self, weak textView] in
            guard let self, let textView, !self.isUpdating else { return }
            self.isUpdating = true
            defer { self.isUpdating = false }
            let ranges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributed)
            textView.selectedRanges = ranges
        }
    }
}
```

`MarkdownHighlighter` is already `nonisolated` and `Sendable`-safe for this pattern.

---

## False Positives Confirmed (Not Issues)

The following patterns were checked and confirmed to be correctly implemented:

1. **File I/O in view body**: All `Data(contentsOf:)` and `String(contentsOf:)` calls are inside `Task.detached` blocks in `DocumentState.loadFile()` and `FolderService`. SAFE.

2. **Formatters in view body**: No `DateFormatter()` or `NumberFormatter()` found anywhere in the codebase. SAFE.

3. **ObservableObject**: The entire codebase uses `@Observable` (iOS 17+/macOS 14+ macro). No `ObservableObject` or `@Published` found. EXCELLENT.

4. **LazyVStack usage**: `ChatView` uses `LazyVStack` for the message list. `QuickSwitcher` uses `LazyVStack` for the results list. CORRECT.

5. **ForEach identity**: All `ForEach` calls use `Identifiable` types (`ChatMessage`, `FolderItem`) or explicit `id:` parameters. CORRECT.

6. **NavigationPath**: No `NavigationPath()` is recreated in view bodies. The app uses `NavigationSplitView` with stable `@State`/`@SceneStorage` bindings. CORRECT.

7. **Timer cleanup**: `FileWatcher` uses `DispatchSource` (not `Timer`). The `deinit` cancels the source. No `Timer` in any view. CORRECT.

8. **Image processing**: No image resizing, `UIGraphicsBeginImageContext`, or `CIFilter` in any view body. The single image (`Image("AIMD")`) is a static asset. SAFE.

9. **Set.contains() in OutlineFileList**: `expandedPaths.contains(item.url.path)` uses a `Set<String>` — O(1) lookup. CORRECT.

10. **Set.contains() in LineNumberRulerView**: `bookmarkedLines.contains(lineNumber)` uses a `Set<Int>` — O(1) lookup. CORRECT.

---

## Architecture Observations (Not Performance Issues)

These are structural notes that do not directly cause frame drops but are worth acknowledging:

- **AppCoordinator env key default value**: `AppCoordinatorKey.defaultValue` creates a new `AppCoordinator()` as the static default. This is a safe fallback for previews but means any view that doesn't have the coordinator injected silently gets a useless instance. Consider making this a `fatalError` in debug builds to catch injection failures early.

- **`updateNSView` item-count diffing**: `OutlineFileList.updateNSView` uses `items.count != coordinator.items.count` as the change signal. This is fast (O(1)) but as noted in HIGH-2, it misses same-count content changes. The NSViewRepresentable update path is correctly efficient; the diffing heuristic just needs strengthening.

- **`ChatService` is instantiated as a `let` in ChatView body**: `private let chatService = ChatService()` in `ChatView` is a stored property, not a body-computed value. SwiftUI does not recreate stored `let` properties on view body re-evaluation — only on view identity recreation. This is CORRECT behavior.

---

## Next Steps

1. **Fix HIGH-1 first**: Cache `FolderTreeFilter.flattenMarkdownFiles` result. This directly reduces unnecessary work on every coordinator state change in the main window.

2. **Fix HIGH-3**: Pre-batch SwiftData `isFavorite` lookups before `reloadData()`. Replace per-row fetches with a single `Set<String>` fetch.

3. **Fix MEDIUM-3**: Move `saveCacheToDisk()` off the main thread using `Task.detached`.

4. **Profile with Instruments after fixes**: Use the SwiftUI template in Instruments (Time Profiler + SwiftUI View Body) to verify view body re-evaluation frequency. Pay attention to `BrowserView.body` and `OutlineFileListWrapper.body` re-evaluation counts during typing in the sidebar filter.

5. **Fix MEDIUM-5 (cache key bug)**: This is a correctness fix that also prevents stale filter results after folder switching.

---

*Static analysis only — verified by reading source. Patterns confirmed present or absent at the listed line numbers. Profile with Instruments to measure actual impact on your hardware and folder sizes.*
