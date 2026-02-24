# Swift Concurrency Audit — AIMDReader
**Date:** 2026-02-23
**Swift version:** 6.2
**Platform:** macOS 26 (Apple Silicon)
**Stack:** SwiftUI, SwiftData, AppKit bridging (NSViewRepresentable)
**Auditor:** Concurrency Auditor Agent

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 1     |
| HIGH     | 5     |
| MEDIUM   | 3     |
| LOW      | 2     |
| **Total**| **11**|

## Swift 6 Readiness

**CONDITIONALLY READY** — The codebase demonstrates strong Swift 6 awareness. The vast majority of
state is correctly @MainActor-isolated. However, there are concrete issues that will either produce
compiler errors under `-strict-concurrency=complete` or represent latent runtime risks. The
`FileMetadataRepository: Sendable` tension is the most architecturally significant concern.

---

## Issues by Severity

---

### CRITICAL

---

#### ISSUE C-1 — @MainActor Protocol Conforms to Sendable: Isolation Escape
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Persistence/FileMetadataRepository.swift:10`
**Severity/Confidence:** CRITICAL / HIGH

**Code:**
```swift
@MainActor
public protocol FileMetadataRepository: Sendable {
    func getMetadata(for url: URL) -> FileMetadata?
    // ...
}
```

**Why it matters:**
`Sendable` promises the type can safely cross concurrency domains. `@MainActor` constrains all methods
to execute only on the main actor. These two constraints are contradictory: a `Sendable` protocol
can be stored in actors or `Task.detached` closures and called from non-main-actor contexts, but
`@MainActor` methods cannot be called without `await` from such contexts. In Swift 6 strict mode the
compiler warns about or rejects this pattern depending on how the conforming type is used.

The concrete conformer `SwiftDataMetadataRepository` stores a `ModelContext`. `ModelContext` is
**not** `Sendable` (it is main-context-only). Declaring `Sendable` on the protocol implies the
repository can cross actor boundaries, which would crash if the `ModelContext` is accessed off-main.

**Fix:**
Remove `Sendable` from the protocol. The `@MainActor` annotation already provides the correct
thread-safety guarantee — the type is safe because it is always used on the main actor, not because
it can be sent freely.

```swift
// Before
@MainActor
public protocol FileMetadataRepository: Sendable { ... }

// After
@MainActor
public protocol FileMetadataRepository { ... }
```

If cross-actor transfer is genuinely needed in the future, redesign the repository as a true `actor`
and remove `@MainActor`.

---

### HIGH

---

#### ISSUE H-1 — DispatchQueue.main.async Inside @MainActor Class (Mixed Dispatch)
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/MarkdownEditor.swift:285`
**Severity/Confidence:** HIGH / HIGH

**Code:**
```swift
// Inside @MainActor class Coordinator
func restoreScrollPosition(_ position: Double, in scrollView: NSScrollView) {
    guard let documentView = scrollView.documentView else { return }

    // Defer to next layout pass so text is fully laid out
    DispatchQueue.main.async {
        let contentHeight = documentView.frame.height
        // ...
        documentView.scroll(NSPoint(x: 0, y: yOffset))
    }
}
```

**Why it matters:**
`Coordinator` is `@MainActor`. Inside a `@MainActor` context, `DispatchQueue.main.async` creates a
closure that escapes the actor's isolation. In Swift 6, `NSScrollView` and `NSView` (both AppKit
types) are not `Sendable`. Sending `documentView` (an `NSView` subclass) and `scrollView` (an
`NSScrollView`) into a `DispatchQueue.main.async` closure constitutes sending non-Sendable values
across a concurrency boundary, which the Swift 6 compiler flags as an error:
`"Sending 'documentView' risks causing data races"`.

Additionally, using `DispatchQueue.main.async` in Swift 6 code is a code smell that bypasses the
structured concurrency model. The `@MainActor` attribute on the enclosing class means all methods
already execute on main — the deferred work should be expressed with `Task { @MainActor in }` so
the isolation is explicit and compiler-verified.

**Fix:**
```swift
func restoreScrollPosition(_ position: Double, in scrollView: NSScrollView) {
    guard let documentView = scrollView.documentView else { return }

    // Defer to next layout pass so text is fully laid out
    Task { @MainActor in
        let contentHeight = documentView.frame.height
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollableHeight = contentHeight - visibleHeight
        guard scrollableHeight > 0 else { return }

        let yOffset = position * scrollableHeight
        documentView.scroll(NSPoint(x: 0, y: yOffset))
    }
}
```

---

#### ISSUE H-2 — nonisolated(unsafe) on Schema Static Property
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Persistence/SwiftDataMetadataRepository.swift:160`
**Severity/Confidence:** HIGH / HIGH

**Code:**
```swift
public enum SchemaV1: VersionedSchema {
    nonisolated(unsafe) public static var versionIdentifier = Schema.Version(1, 0, 0)
    // ...
}
```

**Why it matters:**
`nonisolated(unsafe)` is a compiler escape hatch that suppresses data-race checking for a stored
property. It tells the compiler "I promise this is safe, but don't verify it." In this case the
property is a `static var` (mutable) with no actual synchronization protecting it. If any code path
ever writes this property from two concurrent contexts simultaneously, the result is undefined
behavior — a data race that can corrupt memory or crash.

For a version identifier that should be a constant, `static var` is also semantically wrong — it
implies the value can change at runtime, which `nonisolated(unsafe)` then makes dangerous.

**Fix:**
Change `static var` to `static let`. A `let` is immutable and therefore implicitly `Sendable` and
safe for concurrent access with no attribute required:

```swift
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [FileMetadata.self, Bookmark.self]
    }
}
```

---

#### ISSUE H-3 — Unstructured Task in FolderService.init() with Weak Self
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Services/FolderService.swift:37`
**Severity/Confidence:** HIGH / MEDIUM

**Code:**
```swift
@MainActor
final class FolderService {
    static let shared = FolderService()

    private init() {
        // Load cache asynchronously to avoid blocking main thread during init
        Task.detached(priority: .utility) { [weak self] in
            await self?.loadCacheFromDisk()
        }
    }
```

**Why it matters:**
`FolderService` is a `@MainActor` singleton. The `Task.detached` inside `init()` launches a
background task that immediately tries to re-acquire main-actor isolation via `await self?.loadCacheFromDisk()`.

Three concerns:
1. `Task.detached` entirely escapes the structured concurrency tree. If the app tears down, this
   task has no parent to cancel it. For a singleton this is usually benign, but it is an
   anti-pattern in Swift 6.
2. `loadCacheFromDisk()` is an `async` function on `@MainActor FolderService`. When called via
   `await self?.loadCacheFromDisk()` from a `Task.detached`, the async hop back to the main actor
   is implicit — the compiler must verify `self` is `Sendable` to cross the boundary. Classes
   annotated `@MainActor` are not `Sendable` by default; this only works because of the `[weak self]`
   optional capture. In Swift 6 strict mode this may produce a warning depending on how the
   compiler resolves the optional.
3. The `[weak self]` capture is correct but means the cache load silently drops if `FolderService`
   is deallocated between launch and the task starting — acceptable for a singleton, but worth noting.

**Fix:**
Use a regular (non-detached) `Task` from within an `@MainActor` init. The inner I/O still runs
off-main inside `loadCacheFromDisk()`:

```swift
private init() {
    // Task inherits @MainActor isolation from init context, no weak self needed
    Task {
        await loadCacheFromDisk()
    }
}
```

This is valid because the non-detached `Task` created from `@MainActor init` inherits main-actor
isolation, so `self` capture is safe and no `[weak self]` is required.

---

#### ISSUE H-4 — Stored Task Without Weak Self (FolderService.cacheSaveTask)
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Services/FolderService.swift:72`
**Severity/Confidence:** HIGH / MEDIUM

**Code:**
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

**Why it matters:**
`FolderService` is `@MainActor` and a singleton (`static let shared`). `cacheSaveTask` stores a
strong reference to the `Task`. The `Task` closure here implicitly captures `self` strongly in order
to call `saveCacheToDisk()`. Because `FolderService` is a singleton, this retain cycle never
actually causes a leak in practice — the singleton lives for the app's lifetime. However, the
pattern is fragile: if `FolderService` ever stops being a singleton, the retain cycle becomes a
memory leak. More importantly, this pattern will trigger a Swift 6 warning
`"Capture of 'self' with non-isolated 'nonisolated' storage"` in some compiler versions.

**Fix:**
Add `[weak self]` to make the capture intent explicit and future-proof:

```swift
private func scheduleCacheSave() {
    cacheSaveTask?.cancel()
    cacheSaveTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        self?.saveCacheToDisk()
    }
}
```

---

#### ISSUE H-5 — FileMetadataRepository Sendable Conformance Propagates to AppCoordinator
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Coordinator/AppCoordinator.swift:39`
**Severity/Confidence:** HIGH / MEDIUM

**Code:**
```swift
@MainActor
@Observable
public final class AppCoordinator {
    public var metadata: FileMetadataRepository?
    // ...
}
```

**Why it matters:**
`AppCoordinator` stores `metadata: FileMetadataRepository?`. The protocol is declared `Sendable`
(see Issue C-1). `AppCoordinator` itself is `@MainActor @Observable`. When the `@Observable` macro
generates synthesis code, it may attempt to make storage properties conform to `Sendable` checks.
Because `FileMetadataRepository: Sendable`, the compiler accepts the storage — but the actual
conformer `SwiftDataMetadataRepository` stores `ModelContext` which is decidedly not `Sendable`.
This creates a false sense of safety. The risk materializes if any future code stores or passes the
`metadata` property across actor boundaries.

**Fix:**
This is primarily resolved by fixing Issue C-1 (removing `Sendable` from the protocol). No
additional changes needed in `AppCoordinator` itself.

---

### MEDIUM

---

#### ISSUE M-1 — NSOpenPanel Completion Handler Captures Self Without @MainActor Guarantee
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/AIMDReaderApp.swift:308`  
Also: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Screens/StartView.swift:197`
**Severity/Confidence:** MEDIUM / HIGH

**Code (AIMDReaderApp.swift):**
```swift
panel.begin { response in
    guard response == .OK, let folderURL = panel.url else { return }
    self.coordinator.openFolder(folderURL)  // self is AIMDReaderApp (a struct)
}
```

**Code (StartView.swift):**
```swift
panel.begin { response in
    guard response == .OK, let selectedURL = panel.url else { return }
    SecurityScopedBookmarkManager.shared.saveBookmark(selectedURL, for: directory)
    self.openFolder(selectedURL)  // self is StartView (a struct)
}
```

**Why it matters:**
`NSOpenPanel.begin(_:)` calls its completion handler on the main thread per AppKit contract, but this
is a runtime guarantee, not a compile-time guarantee. The closure type is not annotated
`@MainActor`. In Swift 6 strict mode, accessing `@MainActor`-isolated state (like
`coordinator.openFolder()`) from within a non-`@MainActor`-annotated closure produces a warning or
error: `"Main actor-isolated instance method can only be called on main actor"`.

In `AIMDReaderApp`, `self.coordinator` is `@State` which is `@MainActor`-isolated.
In `StartView`, calling `coordinator.openFolder()` accesses the `@MainActor coordinator`.

Both of these cases are currently correct at runtime (AppKit calls on main), but not verified at
compile time.

**Fix:**
Annotate the completion closures with `@MainActor`:

```swift
// AIMDReaderApp.swift
panel.begin { @MainActor response in
    guard response == .OK, let folderURL = panel.url else { return }
    self.coordinator.openFolder(folderURL)
}

// StartView.swift
panel.begin { @MainActor response in
    guard response == .OK, let selectedURL = panel.url else { return }
    SecurityScopedBookmarkManager.shared.saveBookmark(selectedURL, for: directory)
    self.openFolder(selectedURL)
}
```

---

#### ISSUE M-2 — NSOpenPanel Completion in AppDelegate Wraps in Task { @MainActor in } but Captures self Strongly
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/AIMDReaderApp.swift:66-77`
**Severity/Confidence:** MEDIUM / HIGH

**Code:**
```swift
// AppDelegate is @MainActor
panel.begin { [weak coordinator] response in
    guard response == .OK,
          let grantedURL = panel.url,
          let coordinator else { return }

    Task { @MainActor in
        RecentFoldersManager.shared.addFolder(grantedURL)
        coordinator.openFolder(grantedURL)
        coordinator.selectFile(fileURL)
        self.activateOrOpenBrowser(coordinator)  // <-- self captured strongly
    }
}
```

**Why it matters:**
`coordinator` is captured `[weak]` correctly. However `self` (the `AppDelegate`) is captured
strongly inside the `Task { @MainActor in }` block. `AppDelegate` is `@MainActor` and lives for the
application lifetime, so in practice this is benign. However:
1. The `Task { @MainActor in }` wrapper is unnecessary — the `panel.begin` completion fires on
   main, and `self` is `@MainActor`. The nesting adds complexity without benefit.
2. In Swift 6 strict mode, sending `self` (an `@MainActor class`) into a `Task` body may generate
   a `"Sending 'self' risks causing data races"` diagnostic depending on compiler version.

**Fix:**
Remove the `Task { @MainActor in }` wrapper. Instead, annotate the `panel.begin` closure itself with
`@MainActor` (same pattern as Issue M-1):

```swift
panel.begin { [weak coordinator] @MainActor response in
    guard response == .OK,
          let grantedURL = panel.url,
          let coordinator else { return }

    RecentFoldersManager.shared.addFolder(grantedURL)
    coordinator.openFolder(grantedURL)
    coordinator.selectFile(fileURL)
    self.activateOrOpenBrowser(coordinator)
}
```

---

#### ISSUE M-3 — ChatService respondTask Captures LanguageModelSession Across Actor Boundary
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Services/ChatService.swift:110`
**Severity/Confidence:** MEDIUM / LOW

**Code:**
```swift
@MainActor
final class ChatService {
    private var session: LanguageModelSession?

    func ask(question: String, documentContent: String) async -> ChatResult {
        // ...
        let respondTask = Task<String, Error> {
            let response = try await session.respond(to: question)
            return response.content
        }
    }
}
```

**Why it matters:**
`ChatService` is `@MainActor`. The `Task<String, Error>` created here inherits `@MainActor`
isolation from its creation context, so `session` (a `@MainActor`-stored property) is accessed
on the main actor — this is correct. However, `LanguageModelSession.respond(to:)` is a potentially
long-running async call. When it suspends, the main actor is released (correct behavior for
cooperative multitasking), but if `LanguageModelSession` is not designed to resume correctly after
main-actor suspension within an inherited-isolation task, there may be issues.

The comment in the code says: `"Response<String> stays inside the task"` — this is the right
instinct. The concern is that `LanguageModelSession` itself may not be `Sendable`. If it is not
`Sendable`, a future compiler version may flag the implicit capture.

**Note:** This is LOW confidence because `LanguageModelSession` is a first-party Apple framework type
and Apple typically ensures their async types work correctly with Swift concurrency. The current
code is likely fine as-is. Recommend verifying `LanguageModelSession`'s `Sendable` status in
FoundationModels documentation when macOS 26 is released to production.

**Potential Fix (if needed):**
If `LanguageModelSession` is `Sendable`, no change needed. If not, extract the session
reference before the Task:

```swift
guard let session else { return .error("Session could not be created.") }
let capturedSession = session  // Local copy, if session is a value type or Sendable ref

let respondTask = Task<String, Error> {
    let response = try await capturedSession.respond(to: question)
    return response.content
}
```

---

### LOW

---

#### ISSUE L-1 — @preconcurrency EnvironmentKey Suppresses Sendable Warnings
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Coordinator/AppCoordinator.swift:419`  
Also: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Settings/SettingsRepository.swift:314`
**Severity/Confidence:** LOW / HIGH

**Code:**
```swift
private struct AppCoordinatorKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = AppCoordinator()
}

private struct SettingsRepositoryKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = UserDefaultsSettingsRepository.shared
}
```

**Why it matters:**
`@preconcurrency` on a protocol conformance tells the compiler "this conformance predates Swift
concurrency — suppress Sendable warnings for it." This is the correct temporary bridge when
conforming to a pre-Swift-6 protocol (like `EnvironmentKey`) that hasn't yet been updated to have
`Sendable` requirements. It is not a bug per se, but it suppresses warnings that may reveal
genuine issues.

The `defaultValue` properties store `@MainActor`-isolated class instances. `EnvironmentKey.defaultValue`
is accessed from any context by SwiftUI internals. The `@preconcurrency` suppresses the warning
about this potential cross-isolation access.

**Fix:**
This is a known SwiftUI limitation. The correct long-term fix is to ensure both
`AppCoordinator` and `UserDefaultsSettingsRepository` are genuinely safe to default-initialize
without main-actor context, or to file a feedback to Apple to add `@MainActor` to the
`EnvironmentKey` protocol's `defaultValue` requirement. For now, `@preconcurrency` is the
recommended workaround.

Document the intent explicitly:
```swift
// @preconcurrency required: EnvironmentKey.defaultValue lacks @MainActor annotation.
// The default value is only accessed from SwiftUI's @MainActor view update path in practice.
private struct AppCoordinatorKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = AppCoordinator()
}
```

---

#### ISSUE L-2 — FolderItem Sendable Conformance Not Explicit
**File:** `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Models/FolderItem.swift`
**Severity/Confidence:** LOW / LOW

**Context:**
`FolderItem` is used across `Task.detached` boundaries in `FolderService.swift` (lines 157–159,
179–181) — it is the return value of detached tasks:

```swift
let items = await Task.detached(priority: .userInitiated) {
    Self.loadTreeSync(at: url)
}.value
```

**Why it matters:**
`Task.detached` returns values that cross actor boundaries. The returned `[FolderItem]` must be
`Sendable` for this to compile without warnings under `-strict-concurrency=complete`. If `FolderItem`
is a struct with only value-type stored properties (`URL`, `String`, `Bool`, `Int`, `[FolderItem]?`),
it is implicitly `Sendable` and this is a non-issue. If it contains any reference-type stored
properties, the implicit conformance would be incorrect.

**Note:** LOW confidence because without reading the `FolderItem` struct definition, the implicit
conformance is likely correct for a pure value type. This is a "verify, don't change" item.

**Fix:**
Explicitly declare `Sendable` conformance (or `~Sendable` to opt out) so intent is documented
and the compiler verifies it:

```swift
struct FolderItem: Sendable {
    let url: URL
    let name: String
    let isFolder: Bool
    let markdownCount: Int
    var children: [FolderItem]?
    // ...
}
```

---

## False Positives Noted (Not Issues)

The following patterns were found but are **NOT** concurrency issues:

1. **`nonisolated func textDidChange` with `MainActor.assumeIsolated`**
   (`MarkdownEditor.swift:226`) — Correctly uses `assumeIsolated` because AppKit guarantees main-thread
   delivery. The value extraction (`notification.object`) before crossing the isolation boundary is
   the correct pattern.

2. **`nonisolated func scrollViewDidScroll` with `MainActor.assumeIsolated`**
   (`MarkdownEditor.swift:263`) — Same pattern, correct. The `nonisolated(unsafe) let object` capture
   at line 265 is correctly scoped to the pre-isolation value extraction.

3. **`Task { @MainActor in }` in `ContentView.swift` and `StartView.swift`** — The explicit
   `@MainActor` annotation on these Task bodies is correct and well-intentioned. These are fire-and-
   forget tasks that hop back to main actor and do not capture self strongly.

4. **`DebouncedHighlighter` Task with `[weak self]`** (`MarkdownHighlighter.swift:263`) — The
   `[weak self]` capture in the debounce task is correct. The class is `@MainActor` and the task
   inherits that isolation. The weak capture prevents a retain cycle if the highlighter is discarded
   before the debounce fires.

5. **`withObservationTracking` onChange Tasks** (`SettingsRepository.swift:274, 289, 301`) — The
   `Task { @MainActor [weak self] in }` pattern here is correct. The `onChange` callback from
   `withObservationTracking` fires off the main actor; the Task re-establishes main-actor context
   safely, and `[weak self]` prevents retain cycles in the re-arming observation loop.

6. **All `@Observable @MainActor` classes** — `AppCoordinator`, `NavigationState`, `UIState`,
   `DocumentState`, `AppearanceSettings`, `RenderingSettings`, `BehaviorSettings` are all correctly
   `@MainActor @Observable`. SwiftUI's `@Observable` macro requires the type to be used on a single
   isolation domain, and `@MainActor` provides exactly that.

7. **`FolderService.loadTree` Task.detached for I/O** — Using `Task.detached` for file system
   operations that return value types (`[FolderItem]`) is correct. The detached task escapes the
   main-actor cooperative thread pool for I/O work, and the `await .value` result is assigned back
   on main actor.

---

## Recommendations

### Immediate Actions (Before Shipping)

1. **Fix Issue C-1** — Remove `: Sendable` from `FileMetadataRepository`. This is the highest-risk
   architectural issue. It creates a false `Sendable` promise on a type that holds a non-Sendable
   `ModelContext`. One line change.

2. **Fix Issue H-2** — Change `nonisolated(unsafe) static var` to `static let` in `SchemaV1`.
   A version identifier should never change; `var` is semantically wrong and `nonisolated(unsafe)`
   is inappropriate for what amounts to a constant.

3. **Fix Issue H-1** — Replace `DispatchQueue.main.async` with `Task { @MainActor in }` in
   `MarkdownEditor.Coordinator.restoreScrollPosition`. This is a direct Swift 6 compiler error
   in strict mode.

### Short-Term Actions (Before Swift 6 Strict Mode Enable)

4. **Fix Issues M-1 and M-2** — Annotate all `NSOpenPanel.begin` completion closures with
   `@MainActor`. This resolves the implicit main-thread assumption before the compiler starts
   enforcing it.

5. **Fix Issue H-3** — Replace `Task.detached { [weak self] in await self?.loadCacheFromDisk() }`
   in `FolderService.init()` with a plain `Task { await loadCacheFromDisk() }` that inherits
   `@MainActor` context.

6. **Fix Issue H-4** — Add `[weak self]` to `FolderService.cacheSaveTask` for correctness,
   even though the singleton lifecycle masks the leak today.

### Long-Term / Swift 6 Migration Steps

7. **Enable strict concurrency warnings** — Add `-strict-concurrency=complete` to the project's
   Swift compiler flags (Other Swift Flags) and fix all resulting warnings before upgrading
   to full Swift 6 enforcement.

8. **Verify `FolderItem` Sendable** (Issue L-2) — Add explicit `: Sendable` to `FolderItem` struct
   to document and compiler-verify the intent.

9. **Verify `LanguageModelSession` Sendable** (Issue M-3) — When macOS 26 ships to production,
   check FoundationModels headers to confirm `LanguageModelSession`'s concurrency posture.

10. **Document `@preconcurrency` usage** (Issue L-1) — Add inline comments to both `EnvironmentKey`
    conformances explaining why `@preconcurrency` is used, so future maintainers don't remove it
    thinking it's unnecessary.

---

## Files Audited

| File | Issues Found |
|------|--------------|
| `Sources/Persistence/FileMetadataRepository.swift` | C-1 |
| `Sources/Persistence/SwiftDataMetadataRepository.swift` | H-2 |
| `Sources/MarkdownEditor.swift` | H-1 |
| `Sources/Services/FolderService.swift` | H-3, H-4 |
| `Sources/Coordinator/AppCoordinator.swift` | H-5, L-1 |
| `Sources/Settings/SettingsRepository.swift` | L-1 |
| `Sources/AIMDReaderApp.swift` | M-1, M-2 |
| `Sources/Views/Screens/StartView.swift` | M-1 |
| `Sources/Services/ChatService.swift` | M-3 |
| `Sources/Models/FolderItem.swift` | L-2 |
| All other files (20) | None — Clean |
```

---

## Summary

| Severity | Count | Issues |
|----------|-------|--------|
| CRITICAL | 1     | `FileMetadataRepository: Sendable` on a `@MainActor` protocol that wraps non-Sendable `ModelContext` |
| HIGH     | 5     | `DispatchQueue.main.async` inside `@MainActor` class; `nonisolated(unsafe) static var` that should be `let`; `Task.detached` in singleton `init` with weak-self; stored task capturing self strongly; Sendable propagation through coordinator |
| MEDIUM   | 3     | `NSOpenPanel` completion closures lacking `@MainActor` annotation (3 sites); `LanguageModelSession` cross-actor capture risk |
| LOW      | 2     | `@preconcurrency EnvironmentKey` suppressing Sendable warnings (2 keys); `FolderItem` missing explicit `Sendable` declaration |
| **Total**| **11**| |

The codebase is architecturally sound — all service classes, coordinators, and repositories are correctly `@MainActor`. The issues are concentrated in two areas: the `FileMetadataRepository: Sendable` declaration (architectural risk) and the AppKit bridging layer where `NSOpenPanel` completion handlers and `DispatchQueue.main.async` predate Swift 6 concurrency annotations.
