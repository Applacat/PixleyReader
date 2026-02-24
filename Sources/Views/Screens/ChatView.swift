import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
import AppKit

// MARK: - Chat View

/// The right panel containing AI Chat functionality.
/// Uses Apple Foundation Models for on-device AI inference.
/// Shows "Thinking..." while awaiting, then full response at once
/// (plain text respond(to:) doesn't support token streaming).
@available(macOS 26, *)
struct ChatView: View {

    @Environment(\.coordinator) private var coordinator

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var isWaitingForDocument = false
    @State private var askTask: Task<Void, Never>?
    @State private var initialQuestionTask: Task<Void, Never>?
    @State private var showResetBanner = false

    // Service for business logic — @State ensures single instance per view identity
    @State private var chatService = ChatService()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()

            // Content based on FM availability
            if SystemLanguageModel.default.availability != .available {
                fmUnavailableView
            } else if coordinator.navigation.selectedFile == nil {
                noFileView
            } else {
                chatContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: coordinator.ui.initialChatQuestion) { _, newValue in
            if newValue != nil {
                initialQuestionTask?.cancel()
                initialQuestionTask = Task { await handleInitialQuestion() }
            }
        }
        .onChange(of: coordinator.navigation.selectedFile) { _, _ in
            // File changed — don't clear chat, but note the context shift
        }
        .onDisappear {
            cancelAllTasks()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AI Chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                // Turn counter
                if chatService.turnCount > 0 {
                    Text("Turn \(chatService.turnCount)/\(ChatConfiguration.maxTurnsBeforeReset)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                if !messages.isEmpty {
                    Button("Forget", systemImage: "eraser.line.dashed") {
                        clearChat()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Forget conversation (ESC)")
                    .accessibilityLabel("Clear conversation history")
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func clearChat() {
        cancelAllTasks()
        messages.removeAll()
        showResetBanner = false
        chatService.resetSession()
    }

    private func cancelAllTasks() {
        askTask?.cancel()
        askTask = nil
        initialQuestionTask?.cancel()
        initialQuestionTask = nil
    }

    // MARK: - FM Unavailable View

    private var fmUnavailableView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "apple.intelligence")
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Apple Intelligence Required")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enable Apple Intelligence in System Settings > Apple Intelligence & Siri to use AI Chat.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - No File View

    private var noFileView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("AI Chat")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select a file to ask questions about it")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Auto-reset banner
                        if showResetBanner {
                            resetBanner
                                .id("resetBanner")
                        }

                        if messages.isEmpty {
                            emptyChat
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isLoading) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            Divider()
            inputArea
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: String
        if isLoading {
            target = "loading"
        } else if let last = messages.last {
            target = last.id.uuidString
        } else {
            return
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            proxy.scrollTo(target, anchor: .bottom)
        } else {
            withAnimation {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    // MARK: - Reset Banner

    private var resetBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption)
            Text("Context limit reached. Starting fresh conversation.")
                .font(.caption)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    // MARK: - Empty Chat

    private var emptyChat: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("Ask about this document")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask a question...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(inputText.isEmpty || isLoading)
            .accessibilityLabel("Send message")
        }
        .padding(16)
    }

    // MARK: - Actions

    private func handleInitialQuestion() async {
        guard let question = coordinator.consumeInitialChatQuestion() else { return }

        isWaitingForDocument = true
        defer { isWaitingForDocument = false }

        if coordinator.document.content.isEmpty {
            let didLoad = await waitForDocumentContent(timeout: .seconds(3))
            guard didLoad else {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "Unable to load the document. Please try selecting it again from the sidebar."
                )
                messages.append(errorMessage)
                return
            }
        }

        let userMessage = ChatMessage(role: .user, content: question)
        messages.append(userMessage)
        await askAI(question)
    }

    private func waitForDocumentContent(timeout: Duration) async -> Bool {
        if !coordinator.document.content.isEmpty { return true }

        let document = coordinator.document
        let deadline = ContinuousClock.now + timeout

        while document.content.isEmpty {
            guard !Task.isCancelled else { return false }
            guard ContinuousClock.now < deadline else { return false }
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = document.content
                } onChange: {
                    continuation.resume()
                }
            }
        }
        return true
    }

    @MainActor
    private func sendMessage() {
        // Validate input
        switch ChatInputValidator.validate(inputText) {
        case .failure(.empty):
            return
        case .failure(.tooLong(let max)):
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Your question is too long. Please keep questions under \(max) characters."
            )
            messages.append(errorMessage)
            return
        case .success(let question):
            let userMessage = ChatMessage(role: .user, content: question)
            messages.append(userMessage)
            inputText = ""

            askTask?.cancel()
            askTask = Task {
                await askAI(question)
            }
        }
    }

    /// State-as-Bridge pattern:
    /// 1. Synchronous state mutation (isLoading = true) before await
    /// 2. Async boundary delegated to chatService.ask()
    /// 3. Synchronous state update (isLoading = false, messages.append) after await
    @MainActor
    private func askAI(_ question: String) async {
        isLoading = true
        defer {
            isLoading = false
        }

        let result = await chatService.ask(
            question: question,
            documentContent: coordinator.document.content
        )

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let content):
            messages.append(ChatMessage(role: .assistant, content: content))

        case .successWithReset(let content):
            showResetBanner = true
            messages.append(ChatMessage(role: .assistant, content: content))

        case .error(let errorContent):
            messages.append(ChatMessage(role: .assistant, content: errorContent))

        case .cancelled:
            break
        }
    }
}

// MARK: - Message Bubble

@available(macOS 26, *)
struct MessageBubble: View {

    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            Text(message.content)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .textSelection(.enabled)

            if message.role == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .accessibilityValue(message.role == .user ? "Your message" : "Assistant response")
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .accentColor
        case .assistant:
            return Color.primary.opacity(0.08)
        }
    }
}
