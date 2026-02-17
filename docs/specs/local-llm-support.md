# Local LLM Support — Specification

**Feature:** Replace Foundation Models with Ollama for AI Chat
**Date:** 2026-02-05
**Status:** Ready for implementation

---

## Problem Statement

Apple Foundation Models (3B, 4096-token context) is insufficient for document Q&A. After 4-5 exchanges the context window fills up, the "Memory" gauge under-reports usage, and the model's invisible internal history causes silent failures. The on-device model is too limited for real conversation about markdown documents.

## Solution

Replace Foundation Models with Ollama — a local LLM server that runs on Apple Silicon. Users choose and download models (3B to 14B+) with 32K+ context windows. All inference stays on-device. No external dependencies added (HTTP client built with URLSession).

## Scope

### In Scope
- OllamaClient HTTP service (URLSession, no dependencies)
- Settings → AI tab (Ollama status, model download/management)
- ChatService rewrite (Ollama streaming, document-per-message)
- Streaming token-by-token UI in ChatView
- Remove all Foundation Models code
- Curated model recommendations (small/medium/large)
- Ollama status polling (60s lightweight check)
- Chat panel empty states (no Ollama, no model → Settings CTA)

### Out of Scope
- Cloud LLM backends (ChatGPT, Claude API)
- Text selection context ("explain this section")
- Chat persistence across app sessions
- Auto-install Ollama (user installs manually)
- Custom/fine-tuned models
- Multiple simultaneous model loading

---

## User Stories

### US-1: OllamaClient Service

**Description:** Build a thin HTTP client for the Ollama REST API.

**Endpoints:**
- `GET /api/tags` — list installed models
- `POST /api/chat` — send messages, stream response
- `POST /api/pull` — download a model (stream progress)
- `GET /api/show` — model details (context size, parameters)
- `GET /` or `HEAD /` — health check (is Ollama running?)

**Acceptance Criteria:**
- [ ] OllamaClient is a standalone service in `Sources/Services/OllamaClient.swift`
- [ ] Uses URLSession with async/await, no external dependencies
- [ ] `/api/chat` returns an `AsyncThrowingStream<String, Error>` for streaming tokens
- [ ] `/api/pull` returns an `AsyncThrowingStream<PullProgress, Error>` for download progress
- [ ] `/api/tags` returns `[OllamaModel]` with name, size, modified date
- [ ] `/api/show` returns model details including context length
- [ ] Health check returns `Bool` (connection succeeded or refused)
- [ ] All requests have a configurable base URL (default `http://localhost:11434`)
- [ ] Errors are typed: `.connectionRefused`, `.modelNotFound`, `.serverError(String)`
- [ ] `swift build` passes

### US-2: Settings AI Tab

**Description:** Add a dedicated AI tab to Settings for Ollama management.

**Layout:**
```
┌─────────────────────────────────────┐
│ ● Ollama Status: Running            │
│   (or: Not Found — Install Ollama)  │
├─────────────────────────────────────┤
│ Active Model: [llama3.2:3b ▾]       │
├─────────────────────────────────────┤
│ Recommended Models                  │
│ ┌─────────────────────────────────┐ │
│ │ 🟢 llama3.2:3b    2.0 GB  [✓] │ │
│ │ ⬇️  llama3.1:8b    4.7 GB  [↓] │ │
│ │ ⬇️  qwen2.5:14b    9.0 GB  [↓] │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Download progress:                  │
│ [████████░░░░░░░░] 47% llama3.1:8b  │
└─────────────────────────────────────┘
```

**Acceptance Criteria:**
- [ ] New "AI" tab in SettingsView
- [ ] Shows Ollama connection status (green dot = running, red = not found)
- [ ] When not found: shows "Install Ollama" with link to ollama.com
- [ ] Active model picker dropdown (populated from `/api/tags`)
- [ ] Curated model list with 3 tiers:
  - Small: `llama3.2:3b` (~2 GB)
  - Medium: `llama3.1:8b` (~5 GB)
  - Large: `qwen2.5:14b` (~9 GB)
- [ ] Each model shows: installed status, size, download/delete button
- [ ] Download button triggers `/api/pull` with progress bar
- [ ] Delete button removes model via Ollama API
- [ ] Selected model persisted in UserDefaults via SettingsRepository
- [ ] `swift build` passes

### US-3: ChatService Rewrite + Streaming UI

**Description:** Replace Foundation Models with Ollama in ChatService. Add streaming token display in ChatView.

**Chat Flow:**
1. User types question, presses send
2. ChatService builds messages array:
   - System message: instructions + full document content
   - All previous messages (user + assistant)
   - New user message
3. POST to `/api/chat` with `stream: true`
4. Tokens stream back, ChatView appends to current assistant message in real-time
5. When stream completes, message is finalized

**Acceptance Criteria:**
- [ ] ChatService uses OllamaClient instead of LanguageModelSession
- [ ] Document content sent as system message context with EVERY request
- [ ] Full conversation history sent with each request (Ollama is stateless)
- [ ] Response streams token-by-token into ChatView
- [ ] Assistant message bubble updates live as tokens arrive
- [ ] "Thinking..." indicator shown until first token arrives
- [ ] Replace "Memory" gauge with model info label: "model-name · context-size"
- [ ] Error handling: connection refused → "Ollama not running" message
- [ ] Error handling: model not found → "No model selected" with Settings link
- [ ] "Forget" button clears messages array (no session to reset)
- [ ] `swift build` passes

### US-4: Remove Foundation Models + Cleanup

**Description:** Remove all Foundation Models imports, code, and configuration.

**Acceptance Criteria:**
- [ ] `import FoundationModels` removed from all files
- [ ] `LanguageModelSession` references removed
- [ ] `SystemLanguageModel.default.availability` checks removed
- [ ] `ChatConfiguration` constants updated (remove FM-specific: `maxContextTokens`, `charsPerToken`, `maxContextChars`, `maxContextLength`, `promptOverhead`)
- [ ] Dead constants removed: `conversationDocExcerpt`, `recentMessageCount`, `maxHistoryChars`
- [ ] `ContextEstimate` struct removed or replaced with simple model info
- [ ] `@Generable`/`@Guide` macros in AIMDIntent.swift — decide: remove or keep with stub
- [ ] ChatView availability checking flow removed (no more `isCheckingAvailability`)
- [ ] ChatView unavailable view replaced with Ollama-specific states
- [ ] `ContextMode` enum removed
- [ ] `swift build` passes with zero FoundationModels references
- [ ] grep confirms: `grep -r "FoundationModels" Sources/` returns nothing

### US-5: Ollama Status Polling + Empty States

**Description:** Background polling for Ollama availability and proper empty states in ChatView.

**Acceptance Criteria:**
- [ ] OllamaClient health check runs every 60 seconds (lightweight HEAD request)
- [ ] Status stored on a shared observable (e.g., `OllamaStatus` on AppCoordinator or standalone)
- [ ] ChatView reads status to decide which view to show:
  - Ollama not running → "Ollama is not running. Open Settings to get started." + Settings button
  - Ollama running, no model → "No AI model installed. Go to Settings to download one." + Settings button
  - Ollama running, model ready → Show chat interface
- [ ] Settings AI tab also reads shared status (no duplicate polling)
- [ ] Poll timer paused when app is not active (respects `NSApplication` state)
- [ ] Poll uses `tolerance` on timer for energy efficiency
- [ ] `swift build` passes

### US-6: Welcome Flow Update

**Description:** Simplify the "Read Sample Files" button now that FM is removed.

**Acceptance Criteria:**
- [ ] "Read Sample Files" opens welcome folder and selects first file (no auto-chat)
- [ ] Remove `openWelcomeFolderWithPrompt()` from StartView
- [ ] Remove `openWithFileContext()` from AppCoordinator
- [ ] Remove `initialChatQuestion` from UIState
- [ ] Remove `consumeInitialChatQuestion()` from AppCoordinator
- [ ] Remove `handleInitialQuestion()` and `waitForDocumentContent()` from ChatView
- [ ] `swift build` passes

---

## Technical Design

### New Files
- `Sources/Services/OllamaClient.swift` — HTTP client for Ollama API
- `Sources/Models/OllamaModels.swift` — Codable models for API responses
- `Sources/Views/Screens/AISettingsView.swift` — Settings AI tab

### Modified Files
- `Sources/Services/ChatService.swift` — Rewrite to use OllamaClient
- `Sources/Views/Screens/ChatView.swift` — Streaming UI, new empty states, remove FM flow
- `Sources/Views/Screens/SettingsView.swift` — Add AI tab
- `Sources/Views/Screens/StartView.swift` — Simplify welcome flow
- `Sources/Coordinator/AppCoordinator.swift` — Add Ollama status, remove FM-specific methods
- `Sources/Models/ChatConfiguration.swift` — Remove FM constants, add Ollama config
- `Sources/Settings/SettingsRepository.swift` — Add selectedModel, ollamaBaseURL settings

### Deleted/Gutted Files
- `Sources/Models/AIMDIntent.swift` — Remove `@Generable`/`@Guide` (or stub)
- `Sources/Views/Screens/AITestView.swift` — Remove FM test view

### Data Model

```swift
// OllamaModels.swift
struct OllamaModel: Codable, Identifiable {
    let name: String
    let size: Int64
    let modifiedAt: String
    var id: String { name }
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
}

struct OllamaChatMessage: Codable {
    let role: String  // "system", "user", "assistant"
    let content: String
}

struct OllamaChatStreamChunk: Codable {
    let message: OllamaChatMessage?
    let done: Bool
}

struct OllamaPullProgress: Codable {
    let status: String
    let total: Int64?
    let completed: Int64?
}

struct OllamaModelInfo: Codable {
    let parameters: String?
    let modelInfo: [String: AnyCodable]?  // contains context_length
}
```

### Ollama API Reference

**Health check:**
```
GET http://localhost:11434/
→ 200 "Ollama is running"
```

**List models:**
```
GET http://localhost:11434/api/tags
→ { "models": [{ "name": "llama3.2:3b", "size": 2000000000, ... }] }
```

**Chat (streaming):**
```
POST http://localhost:11434/api/chat
{ "model": "llama3.2:3b", "messages": [...], "stream": true }
→ {"message":{"role":"assistant","content":"Hello"},"done":false}
→ {"message":{"role":"assistant","content":" world"},"done":false}
→ {"done":true,"total_duration":1234567890}
```

**Pull model:**
```
POST http://localhost:11434/api/pull
{ "name": "llama3.2:3b", "stream": true }
→ {"status":"pulling manifest"}
→ {"status":"downloading","total":2000000000,"completed":500000000}
→ {"status":"success"}
```

**Show model:**
```
POST http://localhost:11434/api/show
{ "name": "llama3.2:3b" }
→ { "parameters": "3B", "model_info": { "context_length": 32768 } }
```

---

## Implementation Phases

### Phase 1: Foundation (US-1, US-2)
- Build OllamaClient service
- Build Settings AI tab with model management
- **Verification:** Settings tab shows Ollama status, can list/download/delete models
- **Build:** `cd PixleyWriter && swift build`

### Phase 2: Core (US-3, US-5)
- Rewrite ChatService to use OllamaClient
- Add streaming token display to ChatView
- Add Ollama status polling + empty states
- **Verification:** Chat works with Ollama, tokens stream in real-time, empty states display correctly
- **Build:** `cd PixleyWriter && swift build`

### Phase 3: Cleanup (US-4, US-6)
- Remove all Foundation Models code
- Simplify welcome flow
- Delete dead code and constants
- **Verification:** `grep -r "FoundationModels" Sources/` returns nothing. Build passes.
- **Build:** `cd PixleyWriter && swift build`

---

## Recommended Models

| Tier | Model | Size | Context | RAM Needed | Best For |
|------|-------|------|---------|------------|----------|
| Small | llama3.2:3b | ~2 GB | 32K | 8 GB+ | Quick answers, low-end Macs |
| Medium | llama3.1:8b | ~5 GB | 32K | 16 GB+ | Good balance of speed and quality |
| Large | qwen2.5:14b | ~9 GB | 32K | 32 GB+ | Best quality, slower |

---

## Non-Functional Requirements

- **NFR-1:** Streaming first-token latency < 2 seconds for small models
- **NFR-2:** No external dependencies (URLSession only)
- **NFR-3:** Ollama status poll uses < 0.1% CPU (HEAD request every 60s with tolerance)
- **NFR-4:** All data stays on-device (localhost only)
- **NFR-5:** Graceful degradation when Ollama stops mid-response

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-6 pass
- [ ] All three implementation phases verified
- [ ] `grep -r "FoundationModels" Sources/` returns nothing
- [ ] `swift build` passes (ignoring pre-existing SwiftData macro errors)
- [ ] Chat streams responses from Ollama
- [ ] Settings AI tab manages models
- [ ] Empty states guide user to Settings

---

## Ralph Loop Command

```bash
/ralph-loop "Implement local LLM support per spec at docs/specs/local-llm-support.md

PHASES:
1. Foundation (US-1, US-2): OllamaClient service + Settings AI tab - verify with swift build + Settings tab shows model list
2. Core (US-3, US-5): ChatService rewrite + streaming UI + status polling - verify with swift build + chat works with Ollama
3. Cleanup (US-4, US-6): Remove Foundation Models + simplify welcome - verify with swift build + grep -r FoundationModels Sources/ returns nothing

VERIFICATION (run after each phase):
- cd PixleyWriter && swift build
- grep -r 'FoundationModels' Sources/ (Phase 3 only)

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```
