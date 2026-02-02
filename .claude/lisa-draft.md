# Pixley Reader v1.1 - Draft Spec

## Decisions Made

1. **Drill-down bug** → Story 4 (first priority)
2. **AppState refactor** → Story 5 (no tech debt policy)
3. **FolderService injectable** → Include in Story 5
4. **Navigation model** → iOS Files app style (push for folders, tap-select for files)
5. **File selection** → List(selection:) binding for native behavior
6. **Markdown count** → .badge(count) modifier
7. **State injection** → All states via @Environment separately
8. **Non-markdown files** → Show but dimmed/disabled
9. **Drop handling duplication** → Leave as-is (minor)

## Execution Order

**Story 4** → **Story 5** → **Story 3**

## Story Details

### Story 4: Fix Drill-Down Bug
- **Root cause:** Security-scoped resource access not maintained for subfolders
- **Fix:** Ensure startAccessingSecurityScopedResource covers subfolder access
- **Verification:** Manual test - Open Documents, drill 3+ levels deep, contents show at each level

### Story 5: State Architecture Refactor
- Split AppState → NavigationState, DocumentState, ChatState, FolderState
- Each injected via @Environment separately
- Make FolderService injectable via protocol
- **Verification:** All existing functionality works unchanged

### Story 3: Native Sidebar Refactor
- iOS Files app style navigation
- List(selection:) binding for file selection
- Label + .badge(count) for folder rows
- Non-markdown files shown but dimmed/disabled
- Remove custom FolderRowView, FileRowView
- **Verification:** Sidebar feels native, could drop into iOS app unchanged

## Out of Scope (v1.1)
- Light mode
- File watching (FSEvents)
- Search across documents
- Window state persistence
- iCloud sync
- AppState god object (MOVED TO STORY 5)
- Drop handling extraction (minor duplication OK)
