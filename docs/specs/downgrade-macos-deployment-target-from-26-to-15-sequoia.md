# Spec: Downgrade macOS Deployment Target from 26 to 15 (Sequoia)

**Version:** 1.2.0 (build 3)
**Created:** 2026-02-15
**Status:** Ready for implementation

## Overview

Lower the macOS deployment target from 26 (Tahoe) to 15 (Sequoia) so the app runs on a wider range of Macs. AI Chat (Foundation Models) remains available only on macOS 26+; on older OS versions, the chat feature is completely hidden and the app functions as a pure markdown reader.

## Problem Statement

Pixley Markdown Reader currently requires macOS 26, limiting its audience to users who have upgraded to Tahoe. The app's core value — browsing and reading markdown files with syntax highlighting — has no dependency on macOS 26. Only the AI Chat feature (Foundation Models) requires it. By lowering the deployment target, the app becomes available to the much larger macOS 15+ user base.

## Scope

### In Scope
- Change deployment target from macOS 26.0 to macOS 15.0
- Gate all Foundation Models usage behind `#available(macOS 26, *)`
- Hide AI Chat UI (toolbar button, inspector panel) on macOS <26
- Hide "AI Chat" Help menu item on macOS <26
- Update Welcome tutorial AI Chat page to note "requires macOS 26 or later"
- Bump version to 1.2.0 (build 3)

### Out of Scope
- BYOK (bring your own API key) for older OS — separate spec
- ChatProvider protocol extraction — defer to BYOK spec
- Intel (x86_64) support — remain Apple Silicon only
- Any new features — this is purely a compatibility change

## API Audit Results

Full audit confirms that **only Foundation Models is macOS 26-exclusive**. All other APIs used are compatible with macOS 15:

| API | Min macOS | Status |
|-----|-----------|--------|
| Foundation Models | 26 | **MUST GATE** |
| SwiftData (@Model, ModelContainer) | 14 | Compatible |
| @Observable macro | 14 | Compatible |
| .inspector() / .inspectorColumnWidth() | 14 | Compatible |
| .defaultLaunchBehavior() | 13 | Compatible |
| .restorationBehavior() | 13 | Compatible |
| NavigationSplitView | 13 | Compatible |
| Task.sleep(for:) | 13 | Compatible |

## User Stories

### US-1: Change Deployment Target

**Description:** Update project configuration to target macOS 15.0.

**Files to modify:**
- `project.yml` — change `deploymentTarget.macOS` from `"26.0"` to `"15.0"`
- `project.yml` — change `MACOSX_DEPLOYMENT_TARGET` from `"26.0"` to `"15.0"`
- `project.yml` — bump `MARKETING_VERSION` to `"1.2.0"` and `CURRENT_PROJECT_VERSION` to `"3"`

**Acceptance Criteria:**
- [ ] `project.yml` has `deploymentTarget.macOS: "15.0"`
- [ ] `project.yml` has `MACOSX_DEPLOYMENT_TARGET: "15.0"`
- [ ] `project.yml` has `MARKETING_VERSION: "1.2.0"` and `CURRENT_PROJECT_VERSION: "3"`
- [ ] `xcodegen generate` succeeds
- [ ] `xcodebuild build` succeeds with no errors

---

### US-2: Gate Foundation Models Behind Availability Check

**Description:** Wrap all `FoundationModels` imports and usage behind `#available(macOS 26, *)` so the app compiles and runs on macOS 15.

**Files to modify:**
- `Sources/Services/ChatService.swift` — wrap entire file's public API in availability
- `Sources/Views/Screens/ChatView.swift` — wrap entire view in availability
- `Sources/Models/ChatConfiguration.swift` — wrap if it references Foundation Models types

**Approach:** Use `#if canImport(FoundationModels)` for the import, and `@available(macOS 26, *)` on the class/struct declarations. The files stay in the project but their types are only available on macOS 26+.

**Acceptance Criteria:**
- [ ] `ChatService` is marked `@available(macOS 26, *)`
- [ ] `ChatView` is marked `@available(macOS 26, *)`
- [ ] `import FoundationModels` is wrapped in `#if canImport(FoundationModels)`
- [ ] Build succeeds targeting macOS 15.0
- [ ] No compiler errors or warnings related to availability

---

### US-3: Hide AI Chat UI on macOS <26

**Description:** On macOS versions before 26, the AI Chat toolbar button and inspector panel are completely hidden. On macOS 26+, behavior is unchanged.

**Files to modify:**
- `Sources/ContentView.swift` — wrap `.inspector()` and chat toolbar button in `if #available(macOS 26, *)`
- `Sources/Coordinator/AppCoordinator.swift` — ensure chat-related state doesn't cause issues on <26

**Acceptance Criteria:**
- [ ] On macOS 26+: AI Chat toolbar button visible, inspector works as before
- [ ] On macOS <26: No AI Chat button in toolbar, no inspector panel
- [ ] `coordinator.toggleAIChat()` is never called on <26
- [ ] Build succeeds with no availability warnings

---

### US-4: Hide AI Chat Help Menu Item on macOS <26

**Description:** The Help menu "AI Chat" item is hidden on macOS <26.

**Files to modify:**
- `Sources/AIMDReaderApp.swift` — wrap the "AI Chat" `Button` in Help menu with `if #available(macOS 26, *)`

**Acceptance Criteria:**
- [ ] On macOS 26+: "AI Chat" appears in Help menu
- [ ] On macOS <26: "AI Chat" does not appear in Help menu
- [ ] Other Help menu items (Help, Browsing Folders, Keyboard Shortcuts) remain visible on all OS versions

---

### US-5: Update Welcome Tutorial

**Description:** Add a note to the AI Chat welcome page explaining the macOS 26 requirement.

**Files to modify:**
- `Resources/Welcome/03-AI-Chat.md` — add a note at the top or bottom: "Note: AI Chat requires macOS 26 (Tahoe) or later."

**Acceptance Criteria:**
- [ ] `03-AI-Chat.md` contains a visible note about the macOS 26 requirement
- [ ] The note is clear and non-technical (e.g., "requires macOS Tahoe or later")
- [ ] File renders correctly in the markdown viewer

---

## Technical Design

### Gating Pattern

Use `@available` on type declarations and `#available` in view bodies:

```swift
// ChatService.swift
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(macOS 26, *)
@MainActor
final class ChatService {
    // ... existing implementation unchanged
}
```

```swift
// ContentView.swift — in browserContent
#if os(macOS)
// Only show inspector + chat button on macOS 26+
.modifier(AIChatModifier(coordinator: coordinator))
#endif

// Separate modifier for clean availability gating
struct AIChatModifier: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .inspector(isPresented: ...) {
                    ChatView()
                        .inspectorColumnWidth(min: 250, ideal: 280, max: 400)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        // AI Chat toggle button
                    }
                }
        } else {
            content
        }
    }
}
```

### No Data Model Changes

SwiftData models (FileMetadata, Bookmark) are macOS 14+ compatible. No changes needed.

### No Window Management Changes

`.defaultLaunchBehavior()` and `.restorationBehavior()` are macOS 13+ compatible. No changes needed.

## Implementation Phases

### Phase 1: Build Configuration + Foundation Models Gating
- [ ] US-1: Change deployment target to macOS 15.0, bump version
- [ ] US-2: Gate ChatService and ChatView behind `@available(macOS 26, *)`
- **Verification:** `cd AIMDReader && xcodegen generate && xcodebuild -scheme AIMDReader build`

### Phase 2: UI Gating + Content Updates
- [ ] US-3: Hide AI Chat UI (toolbar button, inspector) on <26
- [ ] US-4: Hide Help menu "AI Chat" item on <26
- [ ] US-5: Update Welcome tutorial with macOS 26 note
- **Verification:** `cd AIMDReader && xcodegen generate && xcodebuild -scheme AIMDReader build`

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-5 pass
- [ ] Build succeeds: `cd AIMDReader && xcodegen generate && xcodebuild -scheme AIMDReader build`
- [ ] App launches and shows StartView (no crash on any supported macOS)
- [ ] On macOS 26+: All existing functionality works identically to v1.1
- [ ] On macOS <26: App works as markdown reader with no trace of AI Chat

## Ralph Loop Command

```
/ralph-loop "Implement macOS 15 deployment target downgrade per spec at docs/specs/downgrade-macos-deployment-target-from-26-to-15-sequoia.md

PHASES:
1. Build config + FM gating: US-1 (deployment target, version bump) + US-2 (gate ChatService/ChatView behind @available(macOS 26, *)) - verify with xcodegen generate && xcodebuild build
2. UI gating + content: US-3 (hide chat toolbar/inspector on <26) + US-4 (hide help menu item on <26) + US-5 (update Welcome tutorial) - verify with xcodegen generate && xcodebuild build

VERIFICATION (run after each phase):
- cd AIMDReader && xcodegen generate && xcodebuild -scheme AIMDReader build

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```

## Open Questions

None — all questions resolved during interview.

## Implementation Notes

*To be filled during implementation.*
