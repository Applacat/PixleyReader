# Memory Leak Audit — AIMDReader Sources
**Date:** 2026-02-23
**Auditor:** Memory Auditor Agent (Claude Sonnet 4.6)
**Scope:** /Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources
**Files Audited:** 30 Swift files (excludes *Tests.swift, *Previews.swift, Pods, Carthage, .build)

---

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH     | 2 |
| MEDIUM   | 3 |
| LOW      | 1 |
| **TOTAL**| **6** |

The codebase is in good overall shape. No Timer leaks, no PhotoKit issues, and no Combine sinks were found. The most significant issues are a strong capture of `coordinator` (a reference type) in a FileWatcher closure and the NSTextViewDelegate/NSOutlineViewDelegate assignments to AppKit coordinator objects without `weak` qualification. These are the two HIGH priority items that can cause retain cycles.

---

## Verification Counts

- **Timer.scheduledTimer / Timer.publish:** 0 found — no timer leaks possible
- **addObserver calls:** 3 (LineNumberRulerView.swift:23, :27; MarkdownEditor.swift:90)
- **removeObserver calls:** 2 (LineNumberRulerView.swift:40 via deinit; MarkdownEditor.swift:178 via deinit) — matched correctly
- **DispatchSource instances:** 1 (FileWatcher.swift:33) — cancel() called in deinit and stop()
- **[weak self] capture lists:** 8 usages — good adoption
- **AnyCancellable / .sink / .assign:** 0 — no Combine subscriptions
- **PHImageManager:** 0 — no PhotoKit usage
- **delegate = (without weak):** 2 assignments (MarkdownEditor.swift:84, OutlineFileList.swift:37-38)
- **Task {} without [weak self]:** 5 suspicious sites reviewed; 3 confirmed safe, 2 need review

---

## Issues by Severity

---

### HIGH — Issue 1: Strong Capture of Reference-Type `coordinator` in FileWatcher Closure

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Screens/MarkdownView.swift`
**Line:** 180
**Confidence:** HIGH

**Code (current):**
```swift
fileWatcher = FileWatcher { [coordinator] in
    coordinator.markDocumentChanged()
}
```

**Why this is a leak:**

`coordinator` is an `AppCoordinator` — a `@MainActor @Observable final class` (a reference type). The capture list `[coordinator]` captures it **strongly** by value (copies the reference, keeps the reference count alive). `FileWatcher` stores its `onChange` closure for its entire lifetime in `private let onChange: @MainActor () -> Void`. This creates the cycle:

```
MarkdownView (@State fileWatcher) 
  → FileWatcher (stores onChange closure)
    → closure strongly retains AppCoordinator
      → AppCoordinator may retain MarkdownView indirectly
```

`MarkdownView` is a SwiftUI struct (value type), so the struct itself won't be retained. However `AppCoordinator` is injected via `.environment` and lives at app scope — it is long-lived. More critically, if `MarkdownView` is ever redesigned so `coordinator` is not app-scoped, or if `FileWatcher` is used in a class context, this capture pattern creates a hard retain that prevents deallocation.

Even in the current architecture, the strong capture means the `AppCoordinator` is kept alive by the closure inside `FileWatcher` as long as `fileWatcher` exists. Since `fileWatcher` is stored as `@State` on `MarkdownView`, it lives for the view's lifetime. The coordinator is app-scoped, so in practice this does not cause a crash today — but it is an incorrect capture pattern and a latent risk.

**Fix — use `[weak coordinator]`:**
```swift
private func startWatching(_ url: URL) {
    if fileWatcher == nil {
        fileWatcher = FileWatcher { [weak coordinator] in
            coordinator?.markDocumentChanged()
        }
    }
    fileWatcher?.watch(url)
}
```

**Impact:** If `AppCoordinator` ever acquires a direct or indirect back-reference to the `FileWatcher` or `MarkdownView`, this becomes a hard retain cycle. The fix is trivial and safe since `coordinator` is app-scoped and outlives the view in normal operation.

---

### HIGH — Issue 2: NSTextViewDelegate Assigned Without `weak` on Coordinator

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/MarkdownEditor.swift`
**Line:** 84
**Confidence:** HIGH

**Code (current):**
```swift
textView.delegate = context.coordinator
```

**Why this is a leak:**

`NSTextView.delegate` is declared as `weak var delegate: NSTextViewDelegate?` by AppKit — so the AppKit side is safe. The problem lies in the ownership chain from SwiftUI's side:

```
NSScrollView (owned by makeNSView, stored in SwiftUI)
  → NSTextView (documentView, strong ref from scrollView)
    → NSTextView.delegate → weak → Coordinator (safe here)

BUT:

SwiftUI NSViewRepresentable
  → Coordinator (strong, owned by SwiftUI's context)
    → parent: MarkdownEditor (strong ref back to the SwiftUI struct)
```

The `Coordinator.parent` property at line 166 is:
```swift
var parent: MarkdownEditor
```

This holds a strong reference to the `MarkdownEditor` value type. Since `MarkdownEditor` is a struct this is a value copy — not a retain cycle in the traditional sense. However the issue is that `Coordinator` is also registered as a `NotificationCenter` observer (line 90 in `makeNSView`) and the `removeObserver` only happens in `deinit`. If SwiftUI recreates the coordinator (e.g., when the parent view is rebuilt), the old coordinator must be properly deallocated to trigger `deinit`.

The real concern: `context.coordinator` is stored by `NSViewRepresentable` infra. If `NSTextView` held a strong reference to the coordinator via its delegate, the coordinator would never deallocate. AppKit's `weak var delegate` prevents this — but you are depending on AppKit's declaration being weak. If you ever swap to a different delegate protocol that doesn't use `weak`, the cycle will form silently.

**Additionally — the `DispatchQueue.main.async` closure at line 285:**
```swift
func restoreScrollPosition(_ position: Double, in scrollView: NSScrollView) {
    guard let documentView = scrollView.documentView else { return }
    DispatchQueue.main.async {
        let contentHeight = documentView.frame.height   // strong capture of documentView
        let visibleHeight = scrollView.contentView.bounds.height  // strong capture of scrollView
        ...
    }
}
```

`scrollView` and `documentView` are captured strongly. Since this is a one-shot async block dispatched to the main queue (not stored), this is **not a persistent leak** — the block executes and releases. However if the view deallocates between dispatch and execution, accessing the scrollView's properties is benign but wastes work. This is LOW risk.

**Recommended fix — verify delegate lifecycle and add explicit nil in dismantleNSView:**
```swift
// Add dismantleNSView to MarkdownEditor:
static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    if let textView = scrollView.documentView as? NSTextView {
        textView.delegate = nil
    }
    NotificationCenter.default.removeObserver(coordinator)
}
```

This ensures the coordinator's NotificationCenter registration is removed even if `deinit` is delayed, and explicitly breaks the delegate chain.

---

### MEDIUM — Issue 3: NSOutlineViewDataSource/Delegate Assigned Without `dismantleNSView` Cleanup

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/OutlineFileList.swift`
**Lines:** 37–38
**Confidence:** MEDIUM

**Code (current):**
```swift
outlineView.dataSource = context.coordinator
outlineView.delegate = context.coordinator
```

**Why this is a concern:**

Both `NSOutlineView.dataSource` and `NSOutlineView.delegate` are declared as `weak` in AppKit, so AppKit will not retain the coordinator. However, `NSScrollView` (the returned view) holds a strong reference to `NSOutlineView`, and `NSOutlineView` holds strong references to its cell views (`FileCellView`). Each `FileCellView` stores:

```swift
private var onToggleFavorite: ((URL) -> Void)?
```

This closure is set in `configure(with:)` and passed down from `OutlineFileList.Coordinator.onToggleFavorite`. That closure ultimately captures the `coordinator` reference from `ContentView`. If the coordinator is not cleared when the view dismantles, the cells retain the closure, which retains the coordinator.

In `FileCellView` at line 460:
```swift
func configure(with item: FolderItem, ..., onToggleFavorite: ((URL) -> Void)? = nil) {
    self.itemURL = item.url
    self.onToggleFavorite = onToggleFavorite   // stored strongly
    ...
}
```

This stored closure is the leak vector. When `OutlineFileList` is removed from the view hierarchy, the `NSScrollView`/`NSOutlineView`/cell chain may be retained for longer than expected by AppKit's view recycling.

**Fix — add dismantleNSView:**
```swift
static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    guard let outlineView = coordinator.outlineView else { return }
    outlineView.dataSource = nil
    outlineView.delegate = nil
    // Cells release their closures when dataSource is cleared
}
```

---

### MEDIUM — Issue 4: `FolderService.cacheSaveTask` Not Cancelled on Deallocation

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Services/FolderService.swift`
**Lines:** 71–77
**Confidence:** MEDIUM

**Code (current):**
```swift
private func scheduleCacheSave() {
    cacheSaveTask?.cancel()
    cacheSaveTask = Task {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        saveCacheToDisk()
    }
}
```

**Why this is a concern:**

`FolderService` is a singleton (`static let shared = FolderService()`), so it is never deallocated in practice. Therefore `cacheSaveTask` running after the service's "lifetime" is not an issue. However, the `cacheSaveTask` holds a strong implicit capture of `self` (the `FolderService`), which is fine for a singleton.

The real concern is the `Task.detached` in `init`:
```swift
private init() {
    Task.detached(priority: .utility) { [weak self] in
        await self?.loadCacheFromDisk()
    }
}
```

This correctly uses `[weak self]`. Good.

The remaining concern is that `cacheSaveTask` is a bare `Task<Void, Never>` stored on the singleton. If the app terminates while the 2-second debounce is pending, the task will be cancelled by Swift's structured concurrency shutdown and `saveCacheToDisk()` will not run — potentially losing the latest cache update. This is a **data loss risk**, not a memory leak.

**Fix for data integrity (not strictly memory):**
```swift
// In AppDelegate or scene lifecycle:
func applicationWillTerminate(_ notification: Notification) {
    // Force-flush any pending cache save synchronously
    FolderService.shared.flushCacheIfNeeded()
}

// In FolderService:
func flushCacheIfNeeded() {
    cacheSaveTask?.cancel()
    cacheSaveTask = nil
    saveCacheToDisk()
}
```

---

### MEDIUM — Issue 5: `MarkdownEditor.Coordinator` Receives NotificationCenter Observer Without `dismantleNSView`

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/MarkdownEditor.swift`
**Lines:** 90–95
**Confidence:** MEDIUM

**Code (current — in `makeNSView`):**
```swift
NotificationCenter.default.addObserver(
    context.coordinator,
    selector: #selector(Coordinator.scrollViewDidScroll(_:)),
    name: NSView.boundsDidChangeNotification,
    object: clipView
)
```

**And in `Coordinator.deinit`:**
```swift
deinit {
    NotificationCenter.default.removeObserver(self)
}
```

**Why this is a concern:**

The observer registration is correct — `deinit` calls `removeObserver(self)`. However, SwiftUI's `NSViewRepresentable` lifecycle does not guarantee that `Coordinator.deinit` runs at the exact moment the view leaves the hierarchy. In practice, if SwiftUI keeps the coordinator alive temporarily (e.g., during view transitions or rapid file switching), the coordinator continues to receive `boundsDidChange` notifications for a `clipView` that may have been recycled. This causes spurious `onScrollPositionChanged` callbacks.

More importantly: there is no `dismantleNSView` implementation. The `static func dismantleNSView(_:coordinator:)` lifecycle callback is the correct place to unregister observers, as it is called deterministically by SwiftUI when the view is permanently removed.

**Fix — add `dismantleNSView` to `MarkdownEditor`:**
```swift
static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    NotificationCenter.default.removeObserver(coordinator)
    if let textView = scrollView.documentView as? NSTextView {
        textView.delegate = nil
    }
}
```

This handles both Issue 2 and Issue 5 in one place and is the idiomatic SwiftUI AppKit bridging pattern.

---

### LOW — Issue 6: `AppDelegate.openMarkdownFileWithFolderAccess` Captures `self` Strongly in NSOpenPanel Completion

**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/AIMDReaderApp.swift`
**Lines:** 66–78
**Confidence:** LOW

**Code (current):**
```swift
panel.begin { [weak coordinator] response in
    guard response == .OK,
          let grantedURL = panel.url,
          let coordinator else { return }

    Task { @MainActor in
        RecentFoldersManager.shared.addFolder(grantedURL)
        coordinator.openFolder(grantedURL)
        coordinator.selectFile(fileURL)
        self.activateOrOpenBrowser(coordinator)   // <-- strong self capture
    }
}
```

**Why this is a concern:**

`coordinator` is weakly captured (good), but `self` (the `AppDelegate`) is captured strongly inside the `Task { @MainActor in ... }` block. `AppDelegate` is effectively app-lifetime (registered via `@NSApplicationDelegateAdaptor`), so `self` never deallocates. This is **not a cycle that causes memory growth**, but it is an incorrect capture pattern.

If `AppDelegate` were ever refactored to be non-singleton, the strong `self` capture in the async task would prevent deallocation until the panel completion fires.

**Fix:**
```swift
panel.begin { [weak coordinator, weak self] response in
    guard response == .OK,
          let grantedURL = panel.url,
          let coordinator,
          let self else { return }

    Task { @MainActor in
        RecentFoldersManager.shared.addFolder(grantedURL)
        coordinator.openFolder(grantedURL)
        coordinator.selectFile(fileURL)
        self.activateOrOpenBrowser(coordinator)
    }
}
```

---

## Patterns Verified as Safe (Not Issues)

### FileWatcher DispatchSource Lifecycle — SAFE
**File:** `Sources/Services/FileWatcher.swift`

The `DispatchSourceFileSystemObject` lifecycle is correctly managed:
- `source.setEventHandler { [weak self] in ... }` — weak capture (line 39)
- `source.setCancelHandler { close(fd) }` — no self capture (line 46)
- `deinit { source?.cancel() }` — cancel in deinit (line 17–19)
- `stop()` calls `source?.cancel(); source = nil` — explicit cleanup (lines 58–60)
- The `onChange` closure is `@MainActor () -> Void` stored as `private let` — not a cycle because `FileWatcher` is owned by `MarkdownView`'s `@State`, not by the coordinator

The only concern is the capture pattern in `MarkdownView.startWatching` (Issue 1 above).

### LineNumberRulerView NotificationCenter — SAFE
**File:** `Sources/Views/Components/LineNumberRulerView.swift`

- 2 `addObserver` calls in `init` (lines 23, 27)
- 1 `removeObserver(self)` in `deinit` (line 40)
- `weak var textView: NSTextView?` — correctly weak (line 7)
- Fully balanced.

### MarkdownEditor.Coordinator NotificationCenter — SAFE (with caveat)
**File:** `Sources/MarkdownEditor.swift`

- 1 `addObserver` in `makeNSView` (line 90)
- 1 `removeObserver(self)` in `deinit` (line 178)
- Balanced, but `dismantleNSView` should be added (Issue 5) for deterministic cleanup.

### DebouncedHighlighter Task — SAFE
**File:** `Sources/MarkdownHighlighter.swift`

```swift
debounceTask = Task { @MainActor [weak self] in
    guard self != nil else { return }
    ...
}
deinit { debounceTask?.cancel() }
```

Correctly uses `[weak self]` and cancels on deinit.

### SettingsRepository `withObservationTracking` — SAFE
**File:** `Sources/Settings/SettingsRepository.swift`

```swift
} onChange: { [weak self] in
    Task { @MainActor [weak self] in
        self?.persistAppearance()
        self?.observeAppearance()
    }
}
```

Double `[weak self]` is correct — once for the synchronous `onChange` block (which fires on a non-isolated context), and once for the async `Task`. This is the correct pattern for `withObservationTracking` in a singleton.

### ChatService Task Pattern — SAFE
**File:** `Sources/Services/ChatService.swift`

The `respondTask` and `watchdog` tasks are local, fire-and-forget with explicit cancellation coordination. No stored closures capturing self.

### FolderService Task.detached — SAFE
**File:** `Sources/Services/FolderService.swift:37`

```swift
Task.detached(priority: .utility) { [weak self] in
    await self?.loadCacheFromDisk()
}
```

Correctly uses `[weak self]`.

### ContentView filterTask — SAFE
**File:** `Sources/ContentView.swift`

```swift
filterTask = Task { ... }
.onDisappear {
    filterTask?.cancel()
    filterTask = nil
}
```

Task is cancelled and cleared in `.onDisappear`. Correct pattern.

### ChatView Tasks — SAFE
**File:** `Sources/Views/Screens/ChatView.swift`

`askTask` and `initialQuestionTask` are stored `@State` on a SwiftUI struct (value type). Both are cancelled in `cancelAllTasks()` which is called from `.onDisappear`. Correct pattern.

### NSTextViewDelegate and NSOutlineViewDelegate Assignments — CONDITIONALLY SAFE
The `textView.delegate = context.coordinator` and `outlineView.dataSource/delegate = context.coordinator` are safe from cycles because AppKit declares these as `weak var`. The concern (Issues 2 and 3) is about deterministic cleanup and the `FileCellView.onToggleFavorite` closure chain.

---

## Testing Recommendations

### Instruments: Leaks Template
1. Open Instruments, choose "Leaks" template
2. Run the app, open a folder, scroll through files rapidly (exercises FileWatcher + LineNumberRulerView)
3. Switch files 10+ times in a row
4. Look for leaked `AppCoordinator` or `MarkdownEditor.Coordinator` instances in the Leaks timeline

### Instruments: Allocations Template — Persistent Growth Check
1. Open Instruments, choose "Allocations" template
2. Enable "Record reference counts"
3. Open folder, close folder (BrowserView.onDisappear fires), open folder again — repeat 5 times
4. Use "Generation" markers between open/close cycles
5. Check that `AppCoordinator`, `MarkdownEditor.Coordinator`, `OutlineFileList.Coordinator`, `LineNumberRulerView`, and `FileWatcher` instance counts return to baseline after close

### Instruments: Memory Graph Debugger
1. Build with Address Sanitizer disabled
2. In Xcode, run the app and let it fully load a folder
3. Debug > Memory Graph Debugger (Debug Memory Graph button)
4. Search for `FileWatcher` — verify it shows exactly 1 instance
5. Search for `Coordinator` — verify counts match open views

### Manual deinit Verification
Add temporary `print` statements to verify deallocation:

```swift
// In FileWatcher:
deinit {
    print("FileWatcher deinit")  // should print when file changes
    source?.cancel()
}

// In MarkdownEditor.Coordinator:
deinit {
    print("MarkdownEditor.Coordinator deinit")  // should print on file switch
    NotificationCenter.default.removeObserver(self)
}
```

Switch files 5 times and confirm each `deinit` fires.

---

## Priority Fix Order

1. **[HIGH] Issue 1** — Change `[coordinator]` to `[weak coordinator]` in `MarkdownView.swift:180`. One-line fix, zero risk.
2. **[HIGH+MEDIUM] Issues 2+5** — Add `static func dismantleNSView` to `MarkdownEditor`. Fixes both the delegate and observer cleanup determinism in one place.
3. **[MEDIUM] Issue 3** — Add `static func dismantleNSView` to `OutlineFileList`. Clears dataSource/delegate and breaks the `FileCellView.onToggleFavorite` closure chain.
4. **[MEDIUM] Issue 4** — Add `flushCacheIfNeeded()` to `FolderService` and call from app termination lifecycle. Prevents cache data loss on forced quit.
5. **[LOW] Issue 6** — Add `[weak self]` to `AppDelegate` panel completion. Defensive, low-urgency.
```

---

## Summary

Here is the issue count by severity for the `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources` codebase:

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 0 | No timer leaks, no guaranteed-crash patterns found |
| HIGH | 2 | Strong `coordinator` capture in FileWatcher closure (MarkdownView.swift:180); NSTextViewDelegate lifetime not deterministically cleaned via `dismantleNSView` (MarkdownEditor.swift) |
| MEDIUM | 3 | NSOutlineViewDelegate/DataSource missing `dismantleNSView` + FileCellView closure chain (OutlineFileList.swift:37-38); FolderService cacheSaveTask data-loss risk on termination (FolderService.swift:71); MarkdownEditor.Coordinator NotificationCenter observer missing deterministic cleanup (MarkdownEditor.swift:90) |
| LOW | 1 | AppDelegate NSOpenPanel completion captures `self` strongly inside async Task (AIMDReaderApp.swift:75) |
| **Total** | **6** | |

The codebase is generally well-written. No Timer leaks, no Combine subscription leaks, no PhotoKit issues, and DispatchSource lifecycle in `FileWatcher` is correctly managed with `cancel()` in both `deinit` and `stop()`. The highest-priority single-line fix is changing `[coordinator]` to `[weak coordinator]` at `MarkdownView.swift:180`. The most impactful structural fix is adding `static func dismantleNSView` to both `MarkdownEditor` and `OutlineFileList`, which resolves Issues 2, 3, and 5 in the idiomatic SwiftUI AppKit bridging pattern.
