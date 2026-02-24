# OOD Guide for Pixley Markdown Reader
## Object-Oriented Data Audit & Development Reference

**Project:** Pixley Markdown Reader (macOS markdown browser with AI chat)
**Pattern:** Object-Oriented Data (OOD)
**Last Updated:** February 3, 2026

---

## What is OOD?

**Object-Oriented Data** = Data structures that describe themselves completely through their properties and computed properties, using domain vocabulary.

### The Core Principle
> **Objects that describe themselves make AI integration free and documentation unnecessary.**

When data is self-describing:
- AI reads the schema and understands capabilities
- Business logic lives as computed properties (like math formulas)
- Refactoring = changing the formula, not rewriting scattered code
- Integration cost = O(1)

---

## OOD in Pixley Markdown Reader: Current State Audit

### ✅ Strong OOD Patterns (Keep These)

#### 1. `FolderItem` - Self-Describing File Tree
```swift
struct FolderItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isFolder: Bool
    let isMarkdown: Bool
    let markdownCount: Int  // OOD: Parent = sum of children
    var children: [FolderItem]?
}
```

**Why this is good OOD:**
- Self-describing hierarchy (tree structure is obvious)
- Domain vocabulary: `isFolder`, `isMarkdown`, `markdownCount`
- Emergent behavior: Count naturally bubbles up through tree
- No external calculator needed - structure IS the logic

**The Comment Bug (Line 218 in FolderService.swift):**
```swift
// WRONG: Describes algorithm, not OOD
// Sum children's counts (OOD: parent = sum of children)

// SHOULD BE: Documents the OOD pattern
// OOD: FolderItem objects naturally aggregate their children's counts
// The tree structure makes this computation self-evident
```

#### 2. `ChatMessage` - Self-Describing Conversation
```swift
struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    
    enum Role {
        case user
        case assistant
    }
}
```

**Why this is good OOD:**
- Clear domain vocabulary: `role`, not "sender" or "author"
- Embedded enum keeps finite values typed
- Self-contained: everything needed to understand a message is here

#### 3. `ContextEstimate` - Self-Reporting Metrics
```swift
struct ContextEstimate: Sendable {
    let usedChars: Int
    let maxChars: Int
    let mode: ContextMode
    
    var percentage: Double {
        min(1.0, Double(usedChars) / Double(maxChars))
    }
    
    var isHighUsage: Bool { percentage > 0.9 }
    var isMediumUsage: Bool { percentage > 0.7 && percentage <= 0.9 }
    var modeLabel: String { ... }
    var modeIcon: String { ... }
}
```

**Why this is EXCELLENT OOD:**
- ✅ Computed properties for derived state (not external calculator)
- ✅ Objects teach themselves: `isHighUsage` describes its own state
- ✅ Domain vocabulary: "usage" not "level" or "status"
- ✅ Views can consume directly: `contextEstimate.modeIcon`

**This is the pattern to replicate everywhere.**

---

### ⚠️ Opportunities for Better OOD

#### 1. `AppState` - Too Much Manual Coordination

**Current State:**
```swift
@Observable
final class AppState {
    var rootFolderURL: URL?
    var selectedFile: URL?
    var isAIChatVisible: Bool
    var fileHasChanges: Bool
    var documentContent: String
    
    func setRootFolder(_ url: URL) { ... }
    func closeFolder() { ... }
    func markFileChanged() { ... }
    func clearChanges() { ... }
}
```

**OOD Opportunity:**
Could this object describe its own state more clearly?

```swift
// Potential improvement:
var hasOpenFolder: Bool { rootFolderURL != nil }
var hasSelectedFile: Bool { selectedFile != nil }
var canReload: Bool { selectedFile != nil && fileHasChanges }
var canAskAI: Bool { selectedFile != nil && !documentContent.isEmpty }
```

**Why:** Views currently check these conditions manually. Object should self-report.

#### 2. `RecentFolder` and `RecentItem` - Duplicate Concepts

**Tower of Babel Signal #1: Multiple definitions for same domain concept**

Current:
```swift
struct RecentFolder: Identifiable, Codable { ... }
struct RecentItem: Identifiable, Codable { ... }
```

Both represent "something recently opened with a bookmark."

**OOD Question:** Is this one concept with a type (folder vs file), or truly two concepts?

If one concept:
```swift
struct RecentlyOpened: Identifiable, Codable {
    enum Kind {
        case folder
        case file
    }
    let kind: Kind
    // ...unified properties
}
```

#### 3. `ChatService` - Business Logic Extracted OUT

**Current Pattern: Logic extracted to service**
```swift
final class ChatService {
    func estimateContext(...) -> ContextEstimate { ... }
    func truncateDocument(...) -> (text: String, wasTruncated: Bool) { ... }
    func buildPrompt(...) -> String { ... }
}
```

**OOD Principle #2: Pull logic IN, never extract OUT**

**Alternative OOD Approach:**
```swift
// Option A: Extend ChatMessage with conversation-level capabilities
extension Array where Element == ChatMessage {
    var contextEstimate: ContextEstimate { ... }
    func buildPrompt(with question: String, document: String) -> String { ... }
}

// Option B: Create a Conversation object
struct Conversation {
    var messages: [ChatMessage]
    var documentContent: String
    
    var contextEstimate: ContextEstimate { ... }
    func prompt(for question: String) -> String { ... }
}
```

**Why:** The conversation should describe itself, not require an external service to interpret it.

---

### 🔍 OOD Audit Questions for Pixley Markdown Reader

Before adding features, ask:

1. **Self-Description Test**
   - Can an AI read the object's schema and understand what it can do?
   - Are computed properties teaching capabilities?

2. **Logic Location Test**
   - Is business logic pulled IN to objects as computed properties?
   - Or is it extracted OUT to services/helpers?

3. **View Computation Test**
   - Are views consuming properties or computing them?
   - Example: `ad.isActive` (good) vs `ad.status == .active` (bad)

4. **Tower of Babel Detection**
   - Multiple definitions for same concept? (`RecentFolder` + `RecentItem`)
   - Strings where enums should be? (check for status strings)
   - Parallel structures requiring sync? (arrays that must stay aligned)

5. **O(1) Integration Test**
   - If I add a computed property, does it become instantly available everywhere?
   - Or do I need to wire it through multiple layers?

---

## The Pattern Applied to This Codebase

### Example 1: FolderItem's Emergent Counting

**The Code:**
```swift
// In FolderService.swift
let children = Self.loadTreeSync(at: itemURL)
let mdCount = children.reduce(0) { $0 + $1.markdownCount }
let item = FolderItem(url: itemURL, isFolder: true, 
                      markdownCount: mdCount, children: children)
```

**Why This Is OOD:**
- The `FolderItem` structure naturally expresses parent-child relationships
- `markdownCount` bubbles up through the tree without special logic
- Add a new file type? Just change how leaf nodes count themselves
- No `FolderCalculator` needed - the tree computes itself

**The "Formula" Here:**
```
Leaf node (file): count = 1 if markdown, 0 otherwise
Parent node (folder): count = sum of children's counts
```

Change this formula = change the business logic. That's it.

### Example 2: ContextEstimate's Self-Reporting

**The Code:**
```swift
var isHighUsage: Bool { percentage > 0.9 }
var modeIcon: String {
    switch mode {
    case .fullDocument: return "doc.text"
    case .truncated: return "doc.badge.ellipsis"
    case .conversation: return "bubble.left.and.bubble.right"
    }
}
```

**Why This Is OOD:**
- UI asks the object: "What icon should I show?" → `estimate.modeIcon`
- Business rule: "When is usage high?" → `estimate.isHighUsage`
- Change the threshold? Change the computed property. Views adapt automatically.

**Views consume, never compute:**
```swift
// Good (current code)
.foregroundStyle(meterColor(for: estimate))

// Could be even better:
extension ContextEstimate {
    var meterColor: Color {
        if isHighUsage { return .red }
        else if isMediumUsage { return .orange }
        return .green
    }
}

// Then view just:
.foregroundStyle(estimate.meterColor)
```

---

### Example 3: Tutorial Button - OOD in Action (NEW)

**The Implementation:**
```swift
// In StartView.swift
FolderShortcutButton(
    title: "Show me the tutorial",
    icon: "book.circle",
    action: openWelcomeFolderWithPrompt
)

private func openWelcomeFolderWithPrompt() {
    // ... setup welcome folder ...
    
    // OOD: Use existing infrastructure
    // Same code path as manual interaction
    appState.openWithFileContext(
        fileURL: welcomeFile,
        question: "What is this app and what can I do with it?"
    )
}
```

**Why This Is OOD:**
- ✅ **No special "tutorial mode" code** - uses existing `openWithFileContext()`
- ✅ **Same execution path** as if user manually: opened folder → selected file → typed question
- ✅ **Self-describing button** - label clearly states what it does
- ✅ **O(1) integration cost** - one button, one method call, leverages existing schema
- ✅ **Demonstrates the pattern** - button is hardcoded, but execution flows through OOD infrastructure

**The Pattern Validated:**
This implementation proves the Wanderlust pattern works in Pixley Markdown Reader:
1. **Schema defines capability** (`AppState.openWithFileContext` signature)
2. **UI speaks schema's language** (passes fileURL + question)
3. **No custom routing needed** - same `ChatView` handles both manual and button-triggered prompts
4. **Human and AI converge** on same code path

**Lessons from Wanderlust Applied:**
Just like Wanderlust's "Edit Sheet handles both manual edits and AI edits," Pixley Markdown Reader's "ChatView handles both typed questions and button-triggered questions." The schema unifies all interaction modes.

---

## Refactoring Roadmap (If Pursuing Pure OOD)

### Phase 1: Fix Documentation
- [ ] Update comment on line 218 in `FolderService.swift`
- [ ] Add OOD principle comments to `FolderItem`, `ContextEstimate`
- [ ] Document the emergent counting pattern

### Phase 2: Consolidate Duplicate Concepts
- [ ] Unify `RecentFolder` and `RecentItem` (if same concept)
- [ ] Audit for strings that should be enums
- [ ] Check for parallel structures needing sync

### Phase 3: Pull Logic IN
- [ ] Consider moving `ChatService` logic to conversation objects
- [ ] Add self-describing computed properties to `AppState`
- [ ] Move view computations to object properties

### Phase 4: Prove O(1) Integration
- [ ] Add a new computed property to `FolderItem`
- [ ] Verify it becomes instantly available everywhere
- [ ] Document the integration cost

---

## Key Insights for This Project

### 1. The Folder Tree Is Already Pure OOD
The `FolderItem` hierarchy is the clearest example of OOD in this codebase:
- Self-describing structure
- Emergent aggregation (counts bubble up)
- No external calculator needed
- Change the leaf formula → entire tree adapts

### 2. ContextEstimate Shows the Pattern
This is the template for all other objects:
- Stored properties: `usedChars`, `maxChars`, `mode`
- Computed properties: `percentage`, `isHighUsage`, `modeLabel`
- Views consume: `estimate.modeIcon` (not calculating in view)

### 3. Services Are the Anti-Pattern
`ChatService`, `FolderService` represent extracted logic.

**Question:** Should these exist?

**OOD Answer:** Only if they're truly orchestrating I/O (disk, network).
If they're calculating/transforming data → pull that logic onto the objects.

### 4. The Comment Bug Reveals the Gap
The comment said "OOD: parent = sum of children" but described an algorithm.

**OOD comments should say:**
- "This object describes itself through computed properties"
- "The tree structure makes aggregation self-evident"
- "Add a field here, gain a capability everywhere"

Not: "Here's the math we're doing"

---

## Questions for Exploration

As you continue exploring OOD in this codebase:

1. **Should `ChatService` exist?**
   - Is it truly I/O orchestration (calls to FoundationModels)?
   - Or is it business logic that belongs on conversation objects?

2. **What is a "Conversation"?**
   - Currently: Array of `ChatMessage`
   - Could be: Object that describes itself (has history, context estimate, can build prompts)

3. **Should file watching be OOD?**
   - Currently: `fileHasChanges` flag in `AppState`
   - Could be: `FileObservation` object that describes its own staleness?

4. **What's the relationship between Recent items?**
   - Two types: folder and file
   - One concept with a discriminator? Or truly separate?

5. **Can launch state be more self-describing?**
   - Currently: Enum with external logic determining state
   - Could be: Object that describes why it chose this state?

---

## The Test: Can AI Understand This?

**Good OOD Test:**
Show an AI (not me, a future AI) just the object definitions.

Can it answer:
- "What can a FolderItem do?"
- "How do I know if context usage is high?"
- "What's the difference between totalSpend and aggregateCPC?" (hypothetical)

If the AI must read implementation code to answer → OOD incomplete.
If the AI reads the schema and knows → OOD working.

---

## For Future Development

When adding features:

### ✅ Do This (OOD Way)
```swift
// Adding "recently edited" indicator
extension FolderItem {
    var wasRecentlyModified: Bool {
        guard let modDate = modificationDate else { return false }
        return Date().timeIntervalSince(modDate) < 3600 // 1 hour
    }
}

// View consumes immediately:
if item.wasRecentlyModified {
    Image(systemName: "circle.fill")
        .foregroundStyle(.green)
}
```

### ❌ Don't Do This (Traditional Way)
```swift
// Helper function in some utility
func isRecentlyModified(_ item: FolderItem) -> Bool {
    guard let modDate = item.modificationDate else { return false }
    return Date().timeIntervalSince(modDate) < 3600
}

// View must know to call helper:
if isRecentlyModified(item) { ... }
```

**Why:** First way adds capability to the object. Second scatters knowledge.

---

## References

- **OOD Principles (Sacred):** Core manifesto
- **OOD Commandments:** The 10 inviolable rules
- **OOD Practical UX Applications:** Behavioral fences + modal confirmation pattern
- **This Project:** Pixley Markdown Reader as exploration of OOD in a markdown browser

---

## Status

**Current State:** Partial OOD adoption with new demonstration
- Strong patterns: `FolderItem`, `ContextEstimate`, `ChatMessage`
- Mixed patterns: Services exist but some logic could move to objects
- Opportunities: Consolidate duplicates, pull more logic IN
- **NEW: Tutorial button demonstrates OOD pattern** - "Show me the tutorial" uses existing infrastructure (openWithFileContext) with no special wiring

**Recent Changes (Feb 3, 2026):**
- ✅ Added "Show me the tutorial" button to StartView - demonstrates OOD by reusing existing chat infrastructure
- ✅ Fixed OOD comment in FolderService.swift (line 218) - now properly documents the pattern instead of describing algorithm
- 📝 Understanding validated through Wanderlust 5-minute app example

**This document:** Living reference for auditing and evolving the codebase toward purer OOD.

---

**Last Updated:** February 3, 2026
**For Questions:** Reference the OOD papers or ask about specific objects
