# Test Quality Audit Report: AIMDReader

**Date**: 2026-02-23
**Total Tests**: ~325 across 19 test files

---

## OVER-TESTED (Safe to Remove: ~40 tests)

### Compiler Guarantee Tests

| File | Test Method | Why Low-Value |
|------|------------|---------------|
| SyntaxThemeSettingTests | `testCaseIterable_allCasesPresent()` | Compiler enforces CaseIterable |
| SyntaxThemeSettingTests | `testHeadingScaleSetting_allCases()` | Same — compiler guarantee |
| FolderItemTests | `testHashable_sameURLsSameHash()` | Synthesized Hashable is compiler-verified |
| FolderItemTests | `testHashable_differentURLsDifferentHash()` | Same |
| FolderItemTests | `testId_equalsURLPath()` | Tests struct member assignment |
| FolderItemTests | `testName_equalsLastPathComponent()` | Same |
| FolderItemTests | `testURL_preservedExactly()` | Same |
| FolderItemTests | `testMarkdownCount_storedAsIs()` | Tests default parameter value |
| FolderItemTests | `testMarkdownCount_defaultsToZero()` | Same |
| FolderItemTests | `testChildren_nilForFiles()` | Tests nil default |
| FolderItemTests | `testChildren_emptyArrayForEmptyFolder()` | Tests empty array passthrough |
| ChatMessageTests | `testInit_generatesUniqueUUID()` | Tests UUID() stdlib function |
| ChatMessageTests | `testContent_storedAsIs()` | Tests string property assignment |
| ChatMessageTests | `testContent_emptyString()` | Same |
| ChatMessageTests | `testContent_multilineText()` | Same |
| ChatMessageTests | `testContent_unicodePreserved()` | Same |
| ChatMessageTests | `testRole_userAndAssistant_areDistinct()` | Tests enum case distinction — compiler guarantee |

### Tautological Tests (Mirror = Assertion)

| File | Test Method | Why Low-Value |
|------|------------|---------------|
| ChatConfigurationTests | All 5 "accessibility" tests | Reading a constant and comparing to hardcoded expected value |
| SettingsRepositoryTests | 8 `testDefaultValues_*` tests | Verifying hardcoded defaults match hardcoded assertions |

### Duplicate Coverage

| Test | Exists In | Also In |
|------|-----------|---------|
| AppError warning/error type checks | AppErrorTests.swift | ErrorBannerTests.swift (lines ~183-203) |

### Overcomplete (Consolidation Candidates)

| File | Current | Proposed |
|------|---------|----------|
| SyntaxThemeSettingTests | 11 individual `testRendererTheme_*` tests | 1 parameterized test with 10 data points |

---

## UNDER-TESTED (Critical Gaps: ~30 tests needed)

### ChatService — 0 TESTS (CRITICAL)

Source: `Sources/Services/ChatService.swift`

Missing coverage:
- **Timeout handling**: 30s watchdog races respond() — untested
- **Error handling**: GenerationError.exceededContextWindowSize, .guardrailViolation, .unsupportedLanguageOrLocale
- **Auto-reset**: Session resets after maxTurnsBeforeReset (3) turns
- **Session lifecycle**: startSession(), resetSession(), auto-create on first ask()
- **Cancellation**: Task cancellation vs timeout cancellation distinction
- **ChatResult enum**: .success, .successWithReset, .error, .cancelled paths

Testable without FoundationModels: Mirror the state machine logic (turnCount, didAutoReset, session nil/non-nil). Mock the respond() call.

**Estimate**: 12-15 tests

### FileWatcher — 0 TESTS (CRITICAL)

Source: `Sources/Services/FileWatcher.swift`

Missing coverage:
- **Change detection**: handleFileEvent() only fires when modificationDate changes
- **Deduplication**: Same modificationDate = no callback (line 65)
- **Stop/restart**: stop() cancels source, watch() auto-stops previous
- **Cleanup**: deinit cancels source, setCancelHandler closes fd

Testable: Mirror the modificationDate comparison logic. Test with real temp files for integration.

**Estimate**: 6-8 tests

### FolderService — PARTIAL (HIGH)

Source: `Sources/Services/FolderService.swift`
Existing: `FolderServiceCacheTests.swift` covers cache invalidation only

Missing coverage:
- **loadTreeSync()**: Recursive folder scanning, markdown counting, sort order (folders first, then alpha)
- **loadTreeWithDiffSync()**: Cache hit vs miss paths, unchanged children reused
- **CachedFolder/CachedItem Codable**: Encoding round-trip, corrupted data recovery
- **Hidden file exclusion**: `.isHidden` check in loadTreeSync
- **Permission errors**: `contentsOfDirectory` returns nil → empty array

Testable: loadTreeSync and loadTreeWithDiffSync are `nonisolated static` — directly testable with temp directories.

**Estimate**: 8-10 tests

### FolderTreeFilter — Well-tested, 1 gap

Source: `Sources/Services/FolderTreeFilter.swift`
Existing: `FolderTreeFilterTests.swift` (19 tests)

Missing: `findFirstMarkdown()` has 0 tests. `flattenMarkdownFiles()` has 0 tests.

**Estimate**: 3-4 tests

---

## CODE QUALITY ISSUES

### Thread.sleep() in Tests (Flaky Risk)

`RecentFoldersManagerTests.swift` lines 163, 165, 209, 211:
```swift
Thread.sleep(forTimeInterval: 0.01) // trying to get different Date() values
```
**Fix**: Use explicit Date objects instead of relying on wall-clock timing.

### Task.sleep() in Async Tests

`ErrorBannerTests.swift`, `AsyncDocumentCoordinationTests.swift`:
Tight timing margins (0.1s timeout + 0.15s sleep). Will fail under CI load.
**Fix**: Increase buffer or use XCTestExpectation with longer timeout.

---

## RECOMMENDATIONS (Prioritized)

### P0 — Do Now

1. **Create ChatServiceTests.swift** (12-15 tests)
   - Mirror ChatService state machine (turnCount, didAutoReset, session lifecycle)
   - Mock respond() with immediate success/failure/timeout
   - Test all ChatResult paths

2. **Create FileWatcherTests.swift** (6-8 tests)
   - Mirror handleFileEvent deduplication logic
   - Integration tests with real temp files

3. **Create FolderServiceLoadingTests.swift** (8-10 tests)
   - Use nonisolated static methods directly with temp directories
   - Test sort order, markdown counting, hidden file exclusion

4. **Add FolderTreeFilter gap tests** (3-4 tests)
   - findFirstMarkdown, flattenMarkdownFiles

### P1 — Trim Dead Weight

5. **Delete ~40 compiler guarantee tests** across:
   - FolderItemTests (8 tests)
   - ChatMessageTests (6 tests)
   - ChatConfigurationTests (5 tests)
   - SettingsRepositoryTests (8 tests)
   - SyntaxThemeSettingTests (2 tests)
   - ErrorBannerTests duplicate AppError tests

6. **Fix timing-dependent tests** (3 in RecentFoldersManagerTests)

### P2 — Polish

7. Consolidate 11 theme resolution tests → 1 parameterized
8. Add CachedFolder Codable round-trip tests
9. Add FolderTreeFilter performance test (large tree)

---

## Net Impact

| Metric | Before | After |
|--------|--------|-------|
| Total tests | ~325 | ~315 |
| Over-tested | ~40 | 0 |
| Critical gaps | 3 services | 0 |
| Flaky timing tests | 6 | 0 |
