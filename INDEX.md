# Pixley Reader - Document Index

**Last Updated:** 2026-02-02
**Ground Truth:** Package.swift (Swift 6.2, macOS 26)

---

## Status Legend

| Status | Meaning |
|--------|---------|
| CURRENT | Reflects reality, use as reference |
| STALE | Outdated, conflicts with reality |
| ARCHIVE | Historical, kept for reference only |
| MISSING | Needed but doesn't exist |

---

## Ground Truth (Code)

| File | Status | Notes |
|------|--------|-------|
| `Package.swift` | CURRENT | Swift 6.2, macOS 26 - THE source of truth for targets |
| `Sources/**/*.swift` | CURRENT | 13 files, working v1 functionality |

---

## Specifications

| File | Status | Notes |
|------|--------|-------|
| `docs/specs/pixley-reader-v1.1-revised.md` | CURRENT | Active spec - 3 stories, 2 phases |
| `docs/specs/pixley-reader-v1.1-revised-progress.txt` | CURRENT | Progress tracker for v1.1 |
| `docs/specs/pixley-reader-v1.1.md` | ARCHIVE | Superseded by revised version |
| `docs/specs/pixley-reader-v1.md` | STALE | References Stream, Projects - NOT in code |
| `docs/specs/pixley-reader-v1-lean.md` | STALE | Unknown relation to other specs |
| `docs/specs/pixley-writer-v1.md` | STALE | Wrong product name (Writer vs Reader) |
| `docs/BRD.md` | STALE | References Stream feature - NOT in code |

---

## Configuration

| File | Status | Notes |
|------|--------|-------|
| `CLAUDE.md` | CURRENT | Updated 2026-02-02 - Swift 6.2, native UI refactor |
| `cal/cal.md` | CURRENT | Updated 2026-02-02 - native UI refactor documented |
| `cal/agent-prompts.md` | UNKNOWN | Need to verify agents are current |

---

## Agents

| File | Status | Notes |
|------|--------|-------|
| `.claude/agents/ood-swiftie.md` | STALE | References iOS 17+ patterns, needs iOS 26 update |
| `.claude/agents/product-visionary.md` | UNKNOWN | Need to verify |

---

## Missing Documentation

| Topic | Why Needed |
|-------|------------|
| iOS 26 / macOS 26 patterns | Apple Happy Path reference for new APIs |
| Liquid Glass design guide | Visual design reference |
| Current architecture diagram | How code actually works today |

---

## Reconciliation Needed

### Priority 1: Fix Ground Truth Docs ✅ DONE 2026-02-02
1. ~~Update `CLAUDE.md`~~ ✅
2. ~~Rewrite `cal/cal.md`~~ ✅
3. Archive stale specs to `docs/archive/` (already done)

### Priority 2: Create Missing Docs
1. iOS 26 / macOS 26 patterns exploration
2. Liquid Glass design exploration
3. Current architecture snapshot

### Priority 3: Update Agents
1. Update ood-swiftie for iOS 26 patterns
2. Verify other agents are current

---

## File Locations

```
PixleyWriter/
├── INDEX.md                    ← YOU ARE HERE
├── CLAUDE.md                   ← [STALE] Main AI reference
├── Package.swift               ← [TRUTH] Build configuration
├── Sources/                    ← [CURRENT] All source code
├── cal/
│   ├── cal.md                  ← [STALE] Journal
│   ├── agent-prompts.md        ← [UNKNOWN]
│   └── inside-out/             ← Exploration journals
├── docs/
│   ├── BRD.md                  ← [STALE]
│   └── specs/
│       ├── pixley-reader-v1.1-revised.md      ← [CURRENT] Active spec
│       ├── pixley-reader-v1.1-revised-progress.txt ← [CURRENT]
│       └── ... (stale files)
└── .claude/
    ├── agents/                 ← [STALE] Need iOS 26 updates
    └── ...
```
