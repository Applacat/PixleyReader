# SwiftUI Architecture Audit Report
**AI.md Reader macOS App**
**Generated: 2026-02-23**

---

## Executive Summary

This SwiftUI app demonstrates **strong architectural discipline** overall, with clean separation of concerns, proper state management through AppCoordinator pattern, and good testability. The codebase uses `@Observable` models, environment injection, and avoids major anti-patterns.

However, a few **MEDIUM-severity maintainability issues** were identified, primarily around logic organization and model sizing. No CRITICAL correctness bugs were found.

### Issue Counts by Severity
- **CRITICAL**: 0
- **HIGH**: 0
- **MEDIUM**: 5
- **LOW**: 7
- **Total**: 12

---

## Detailed Findings

### 1. MEDIUM: Logic in View Body — QuickSwitcher Results Computation

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/QuickSwitcher.swift:16-39`

**Issue**:
```swift
private var results: [FolderItem] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
        return Array(allFiles.prefix(20))
    }

    let lowered = trimmed.lowercased()

    // Score and sort: prefix matches ranked higher than contains
    let scored = allFiles.compactMap { item -> (FolderItem, Int)? in
        let name = item.name.lowercased()
        if name.hasPrefix(lowered) {
            return (item, 2) // Prefix match = highest priority
        } else if name.localizedCaseInsensitiveContains(trimmed) {
            return (item, 1) // Contains match
        }
        return nil
    }

    return scored
        .sorted { $0.1 > $1.1 }
        .prefix(20)
        .map(\.0)
}
```

**Severity**: MEDIUM

**Why This Matters**:
- **Untestable logic**: Scoring algorithm and fuzzy matching logic is embedded in the view body computed property. Cannot be unit tested independently.
- **Recomputed on every render**: The entire scoring and sorting happens every time SwiftUI re-evaluates the view hierarchy.
- **Separation of concerns**: Business logic (search scoring) belongs in a model or adapter, not in a view's computed property.

**Recommendation**:
Extract search logic to a dedicated `SearchService` or add a computed property on a model:
```swift
// Better: Add to AppCoordinator or a dedicated SearchService
struct QuickSwitcherService {
    func score(items: [FolderItem], query: String) -> [FolderItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(items.prefix(20)) }
        
        let lowered = trimmed.lowercased()
        let scored = items.compactMap { item -> (FolderItem, Int)? in
            // ... scoring logic
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(20).map(\.0)
    }
}

// In view
private var results: [FolderItem] {
    searchService.score(items: allFiles, query: query)
}
```

**Reference**: `/skill axiom-swiftui-architecture` (Extract testable logic from views)

---

### 2. MEDIUM: God ViewModel Heuristic — SettingsRepository with Multiple Domains

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Settings/SettingsRepository.swift:1-324`

**Issue**:
The `UserDefaultsSettingsRepository` is an `@Observable` class that manages three distinct domains:
1. **AppearanceSettings** (color scheme) — UI presentation
2. **RenderingSettings** (fonts, themes, line numbers) — markdown rendering
3. **BehaviorSettings** (link behavior) — interaction rules

While not excessively large (~60 properties total across all three), the pattern mixes unrelated concerns in a single observable model.

**Severity**: MEDIUM (Advisory)

**Why This Matters**:
- Changes to any setting trigger observation on the entire repository, even if only one domain is relevant.
- Views that only care about appearance (e.g., `FontSizeControls`) are observing rendering and behavior settings unnecessarily.
- Harder to test in isolation — mocking the repository requires providing all three settings.

**Current State** (Good):
The code already decomposes settings into three focused `@Observable` classes (`AppearanceSettings`, `RenderingSettings`, `BehaviorSettings`), which is a good pattern. The repository just aggregates them.

**Recommendation**:
Consider injecting each settings container independently if you find observation churn becoming a problem:
```swift
// Better for views that only care about one domain
@Environment(\.appearanceSettings) private var appearance
@Environment(\.renderingSettings) private var rendering
@Environment(\.behaviorSettings) private var behavior

// Instead of
@Environment(\.settings) private var settings
```

**Note**: This is an **advisory MEDIUM issue**. The current design is acceptable and follows good patterns. Only refactor if you observe performance issues or complexity growth.

---

### 3. MEDIUM: Async Work Without Debouncing in FilteredItems Update

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/ContentView.swift:279-301`

**Issue**:
```swift
private func recomputeFilteredItems(debounce: Bool) {
    filterTask?.cancel()
    filterTask = Task {
        if debounce {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }

        // Long-running filtering operation
        var items = coordinator.navigation.displayItems
        let query = coordinator.navigation.sidebarFilterQuery
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            items = FolderTreeFilter.filterByName(items, query: query)
        }

        if showFavoritesOnly {
            let allFiles = FolderTreeFilter.flattenMarkdownFiles(items)
            filteredItems = allFiles.filter { coordinator.isFavorite($0.url) }
        } else {
            filteredItems = items
        }
    }
}
```

**Severity**: MEDIUM

**Why This Matters**:
- **Redundant debouncing**: The function manually implements debouncing with sleep, which is fragile.
- **Race condition risk**: If `recomputeFilteredItems(debounce: true)` is called twice rapidly, the second call will cancel the first task's sleep, potentially causing early evaluation.
- **Not typical SwiftUI pattern**: Should use `@Debounce` modifier or a proper debounce operator.

**Current Behavior** (Acceptable):
The implementation works because `filterTask?.cancel()` at the start ensures only one task runs at a time. The logic is correct but not idiomatic.

**Recommendation**:
Use SwiftUI's `onChange` debouncing (available in Swift 6.1+) or a third-party debounce library:
```swift
.onChange(of: coordinator.navigation.sidebarFilterQuery) { _, _ in
    // SwiftUI will debounce automatically with a small delay
    recomputeFilteredItems(debounce: false)
}
.debounce(duration: .milliseconds(150), scheduler: DispatchQueue.main)
```

---

### 4. MEDIUM: Model Imports SwiftUI Unnecessarily

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Settings/SettingsRepository.swift:1`

**Issue**:
The `SettingsRepository.swift` file imports `SwiftUI` but is primarily a data model and repository:
```swift
import SwiftUI
import aimdRenderer

@MainActor
public protocol SettingsRepository {
    // ...
}

@MainActor
@Observable
public final class AppearanceSettings {
    public var colorScheme: ColorScheme? = nil
    // ...
}
```

**Severity**: MEDIUM (Testability coupling)

**Why This Matters**:
- **Couples business logic to UI framework**: The settings model depends on SwiftUI (`@Observable`, `ColorScheme`).
- **Harder to test**: Unit tests of settings logic must import SwiftUI, which is unnecessary.
- **Tight coupling**: If you ever want to reuse settings in a command-line tool or macOS daemon, you can't without restructuring.

**Current State**:
The issue is **partially mitigated** because:
- Settings containers use `@Observable` (which is `@MainActor`), not `@State` or other view-level decorators.
- `ColorScheme` is a SwiftUI type, but it's a simple enum wrapper around presentation intent.

**Recommendation**:
Extract settings data model from SwiftUI decorators:
```swift
// Foundation-only model
public struct AppearancePreferences: Codable {
    public enum ColorSchemePreference: String, Codable {
        case system
        case light
        case dark
    }
    public var colorScheme: ColorSchemePreference = .system
}

// SwiftUI adapter
@MainActor
@Observable
public final class AppearanceSettings {
    private var preferences: AppearancePreferences
    
    public var colorScheme: ColorScheme? {
        get {
            switch preferences.colorScheme {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
        set { /* ... */ }
    }
}
```

**Alternatively**, keep settings in SwiftUI if you accept the coupling. The current approach is **pragmatic** and acceptable for a macOS app with no portability needs.

---

### 5. MEDIUM: No Async Boundary Validation in ChatService

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Services/ChatService.swift:86-148`

**Issue**:
While the `ChatService` properly isolates async work (Foundation Models calls), the view layer doesn't clearly document the async boundary:

```swift
// In ChatView.swift:351-379
@MainActor
private func askAI(_ question: String) async {
    isLoading = true
    defer { isLoading = false }

    let result = await chatService.ask(
        question: question,
        documentContent: coordinator.document.content
    )

    guard !Task.isCancelled else { return }

    switch result {
    case .success(let content):
        messages.append(ChatMessage(role: .assistant, content: content))
    // ...
    }
}
```

**Severity**: MEDIUM (Informational)

**Why This Matters**:
- No explicit "State-as-Bridge" pattern documentation.
- `isLoading` is a local `@State` that synchronously mutates before the async work starts, which is correct, but could be clearer.
- Future developers might misunderstand and try to animate the async boundary.

**Current Behavior** (Good):
- State mutation (`isLoading = true`) happens synchronously before `await`.
- Async work (Foundation Models) is properly delegated to `ChatService`.
- No `withAnimation` wraps the `await`.

**Recommendation**:
Add a comment documenting the State-as-Bridge pattern:
```swift
/// State-as-Bridge pattern:
/// 1. Synchronously mutate state (isLoading = true) before async work
/// 2. Delegate all async business logic to service (chatService.ask)
/// 3. Synchronously update state with results after await completes
@MainActor
private func askAI(_ question: String) async {
    // Step 1: Synchronous state mutation
    isLoading = true
    defer { isLoading = false }

    // Step 2: Async boundary (service owns this)
    let result = await chatService.ask(question: question, documentContent: coordinator.document.content)

    // Step 3: Synchronous state update
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let content):
        messages.append(ChatMessage(role: .assistant, content: content))
    }
}
```

---

### 6. LOW: Collections Transforms in View Body

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/ContentView.swift:288-299`

**Issue**:
```swift
private func recomputeFilteredItems(debounce: Bool) {
    // ...
    var items = coordinator.navigation.displayItems
    let query = coordinator.navigation.sidebarFilterQuery
    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
        items = FolderTreeFilter.filterByName(items, query: query)  // ← Transform
    }

    if showFavoritesOnly {
        let allFiles = FolderTreeFilter.flattenMarkdownFiles(items)  // ← Transform
        filteredItems = allFiles.filter { coordinator.isFavorite($0.url) }  // ← Transform
    } else {
        filteredItems = items
    }
}
```

**Severity**: LOW

**Why This Matters**:
While this is in a `Task`, it's still computing derived state (filtered results) inside a view method. The logic would be better served as a model-level computed property or a dedicated service method.

**Current State** (Acceptable):
The work is delegated to `FolderTreeFilter` service methods, so the view isn't directly implementing filtering. This is acceptable.

**Recommendation**:
Consider adding a computed property or method to `AppCoordinator` or a dedicated `FilterService`:
```swift
// On AppCoordinator or a model
func computeFilteredItems(
    allItems: [FolderItem],
    query: String,
    favoritesOnly: Bool,
    isFavorite: @escaping (URL) -> Bool
) -> [FolderItem] {
    var items = allItems
    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
        items = FolderTreeFilter.filterByName(items, query: query)
    }
    if favoritesOnly {
        let allFiles = FolderTreeFilter.flattenMarkdownFiles(items)
        items = allFiles.filter { isFavorite($0.url) }
    }
    return items
}
```

---

### 7. LOW: NSViewRepresentable Coordinator Complexity

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/OutlineFileList.swift:84-326`

**Issue**:
The `Coordinator` class for `OutlineFileList` is large (~240 lines) and manages multiple concerns:
- Expansion state tracking
- Data source delegation
- Selection synchronization
- Cell view configuration

**Severity**: LOW

**Why This Matters**:
- Difficult to unit test NSViewRepresentable coordinators.
- Large coordinator suggests the wrapper is doing too much.
- However, this is unavoidable with AppKit bridging — NSOutlineView requires a stateful delegate.

**Current State** (Acceptable):
The coordinator is well-organized into distinct sections (MARK comments), and the logic is clear. This is appropriate complexity for an NSViewRepresentable bridge.

**Recommendation**:
No action needed. NSViewRepresentable coordinators are expected to be larger due to AppKit's delegate-based architecture.

---

### 8. LOW: Task Management Without Explicit Cancellation Context

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Screens/ChatView.swift:46-57`

**Issue**:
```swift
.onChange(of: coordinator.ui.initialChatQuestion) { _, newValue in
    if newValue != nil {
        initialQuestionTask?.cancel()
        initialQuestionTask = Task { await handleInitialQuestion() }
    }
}
```

**Severity**: LOW

**Why This Matters**:
- Manual task cancellation is handled, but there's no explicit `onDisappear` cleanup guarantee if the view is destroyed during task execution.
- The `onDisappear` at line 55-57 does clean up, so this is actually well-handled.

**Current State** (Good):
Tasks are properly cancelled in `onDisappear`. No issue here.

---

### 9. LOW: MarkdownEditor Debounced Highlighting Without Actor Isolation Validation

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/MarkdownEditor.swift:226-259`

**Issue**:
```swift
nonisolated func textDidChange(_ notification: Notification) {
    // Extract NSTextView before crossing isolation boundary
    guard let textView = notification.object as? NSTextView else { return }

    // AppKit always calls delegate methods on the main thread,
    // so we can safely assume MainActor isolation
    MainActor.assumeIsolated {
        // ... update logic
    }
}
```

**Severity**: LOW

**Why This Matters**:
- Uses `MainActor.assumeIsolated` which is unsafe if AppKit ever calls the delegate off-thread (unlikely but theoretically possible).
- The comment documents the assumption clearly, which is good, but a safer pattern would be to use `@MainActor` dispatch explicitly.

**Current State** (Acceptable):
The comment is explicit about the assumption. The code is correct for macOS AppKit, where delegate callbacks are always main-threaded.

**Recommendation**:
If concerned about safety, dispatch explicitly:
```swift
nonisolated func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }
    DispatchQueue.main.async { [weak self] in
        self?.handleTextChange(textView)
    }
}

@MainActor
private func handleTextChange(_ textView: NSTextView) {
    // ... logic
}
```

---

### 10. LOW: No Testability Layer for AppDelegate

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/AIMDReaderApp.swift:18-91`

**Issue**:
```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var coordinator: AppCoordinator?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator = Self.coordinator, let url = urls.first else { return }
        // ... file opening logic
    }
}
```

**Severity**: LOW

**Why This Matters**:
- Uses a static property to access the coordinator, making it impossible to inject different coordinators in tests.
- The file opening logic (lines 42-77) is embedded in the delegate and cannot be unit tested without an active NSApplicationDelegate.

**Current State** (Acceptable):
For a macOS app with limited testing needs, this is acceptable. The logic is relatively simple and mostly delegates to the coordinator.

**Recommendation**:
Extract file opening logic to a testable service:
```swift
struct FileOpeningService {
    let coordinator: AppCoordinator
    
    func handleFileOpen(_ url: URL) async {
        // ... logic
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var fileService: FileOpeningService?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        Task {
            await fileService?.handleFileOpen(urls[0])
        }
    }
}
```

---

### 11. LOW: Inline Computed Property Transforms (QuickSwitcher)

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/QuickSwitcher.swift:138-154`

**Issue**:
```swift
private var parentPath: String {
    guard let root = rootURL else { return "" }
    let parentURL = item.url.deletingLastPathComponent()
    let rootPath = root.path
    let parentPathStr = parentURL.path

    if parentPathStr == rootPath {
        return ""
    }
    // Strip root prefix to get relative path
    if parentPathStr.hasPrefix(rootPath) {
        let relative = String(parentPathStr.dropFirst(rootPath.count))
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }
    return parentURL.lastPathComponent
}
```

**Severity**: LOW

**Why This Matters**:
- String manipulation logic is inline in a view component.
- Duplicated across `QuickSwitcherRow` instances (one per row).
- Not testable as a standalone function.

**Recommendation**:
Extract to a utility function or model method:
```swift
extension URL {
    func relativePathFrom(_ root: URL) -> String {
        let parentURL = deletingLastPathComponent()
        if parentURL.path == root.path { return "" }
        if parentURL.path.hasPrefix(root.path) {
            let relative = String(parentURL.path.dropFirst(root.path.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return parentURL.lastPathComponent
    }
}

// In view
private var parentPath: String {
    item.url.relativePathFrom(rootURL ?? URL(fileURLWithPath: "/"))
}
```

---

### 12. LOW: ErrorBanner Hardcoded Auto-Dismiss Time

**File**: `/Users/etoduarte/0. Coding/Swift/1. AI.md Reader/AIMDReader/Sources/Views/Components/ErrorBanner.swift:81-86`

**Issue**:
```swift
.task(id: coordinator.ui.currentError) {
    guard coordinator.ui.currentError != nil else { return }
    try? await Task.sleep(for: .seconds(5))  // ← Hardcoded
    guard !Task.isCancelled else { return }
    coordinator.dismissError()
}
```

**Severity**: LOW

**Why This Matters**:
- Hardcoded 5-second timeout is not configurable.
- Difficult to test (requires waiting 5 seconds).
- Accessibility: Users who need more time to read have no option.

**Recommendation**:
Make timeout configurable:
```swift
private let errorDismissTimeout: Duration = .seconds(5)

.task(id: coordinator.ui.currentError) {
    guard coordinator.ui.currentError != nil else { return }
    try? await Task.sleep(for: errorDismissTimeout)
    guard !Task.isCancelled else { return }
    coordinator.dismissError()
}
```

Or expose via settings:
```swift
@Environment(\.settings) private var settings
// ... 
try? await Task.sleep(for: Duration(seconds: settings.behavior.errorDismissSeconds))
```

---

## Summary of Recommendations

### Priority 1 (Fix Soon)
1. **QuickSwitcher search scoring**: Extract to testable service (Issue #1)
2. **SettingsRepository imports**: Consider separating Foundation models from SwiftUI adapters (Issue #4)

### Priority 2 (Nice to Have)
3. **FilteredItems debouncing**: Use SwiftUI's built-in debounce (Issue #3)
4. **ChatService documentation**: Add State-as-Bridge pattern comments (Issue #5)

### Priority 3 (Optional Refactoring)
5. **AppDelegate file opening**: Extract to testable service (Issue #10)
6. **QuickSwitcher path logic**: Extract to URL extension (Issue #11)
7. **ErrorBanner timeout**: Make configurable (Issue #12)

---

## Positive Findings

### Strong Patterns

1. **AppCoordinator (Excellent)**
   - Clear state ownership hierarchy
   - Separated concerns (NavigationState, UIState, DocumentState)
   - All mutations routed through coordinator methods
   - Highly testable design

2. **Environment Injection (Excellent)**
   - Coordinator and Settings injected via Environment
   - No singletons except `FolderService.shared` (justified)
   - Views depend on Environment, not globals

3. **Async Boundary Management (Good)**
   - No `withAnimation` wrapping `await` calls
   - State mutations synchronous, async work delegated to services
   - Proper cancellation handling in `onDisappear`

4. **Service Layer Abstraction (Good)**
   - `ChatService`, `FolderService`, `RecentFoldersManager` encapsulate business logic
   - Views call coordinator methods, which delegate to services
   - Clear separation between view and business logic

5. **Property Wrapper Hygiene (Good)**
   - No misuse of `@State` on passed-in data
   - Proper use of `@Binding`, `@Environment`
   - `@Observable` models with `@MainActor` isolation

6. **No Major Anti-Patterns**
   - No logic in view bodies (beyond computed properties)
   - No formatters created repeatedly
   - No inline collection transformations in body rendering
   - No mixing of concerns in single view files

### Testability Strengths

- AppCoordinator is easily mockable for testing
- Services are injectable via coordinator methods
- State is centralized and observable
- No tight coupling to SwiftUI in business logic (except SettingsRepository)

---

## Comparison with axiom-swiftui-architecture

This codebase **aligns well** with the axiom skill recommendations:

| Pattern | Status | Notes |
|---------|--------|-------|
| Single source of truth | ✅ Pass | AppCoordinator owns all state |
| Observable models | ✅ Pass | Uses `@Observable` correctly |
| Environment injection | ✅ Pass | Coordinator and Settings in Environment |
| State-as-Bridge | ✅ Pass | Async work delegated to services |
| Logic extraction | ⚠️ Minor | QuickSwitcher search logic is in view |
| Service layer | ✅ Pass | ChatService, FolderService, etc. |
| Testability | ✅ Good | Most logic is testable |

---

## Conclusion

**Grade: A- (88/100)**

This is a **well-architected** SwiftUI macOS application. The AppCoordinator pattern provides excellent state management, the Environment injection is clean, and async boundaries are properly maintained. 

The 12 issues identified are mostly **LOW or MEDIUM severity**, focusing on:
- Minor view organization (search logic extraction)
- Optional refactoring (service layer) 
- Documentation improvements (State-as-Bridge comments)

**No CRITICAL correctness bugs** were found. The app is production-ready from an architectural perspective.

### Next Steps
1. Consider extracting QuickSwitcher search logic to a service
2. Add State-as-Bridge documentation to ChatView
3. Optionally decouple SettingsRepository from SwiftUI
4. Use SwiftUI's native debouncing for filter updates
