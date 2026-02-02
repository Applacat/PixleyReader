import SwiftUI
import FoundationModels

// MARK: - Chat View

/// The right panel containing AI Chat functionality.
struct ChatView: View {

    @Environment(AppState.self) private var appState

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var aiAvailable: Bool? = nil
    @State private var documentTruncated = false

    // Context window tracking
    private static let maxTokens = 4096  // Foundation Models approximate limit
    private static let charsPerToken = 4  // Rough estimate for English text
    private static let maxContextChars = maxTokens * charsPerToken  // ~16K chars

    /// Estimated context usage for the next request
    private var contextEstimate: ContextEstimate {
        let docLength = appState.documentContent.count
        let hasHistory = !messages.isEmpty

        if hasHistory {
            // Conversation mode: brief doc (2K) + chat history
            let historyChars = messages.suffix(6).reduce(0) { $0 + $1.content.count }
            let docChars = min(2000, docLength)
            let totalChars = docChars + historyChars + 200 // 200 for prompt overhead
            return ContextEstimate(
                usedChars: totalChars,
                maxChars: Self.maxContextChars,
                mode: .conversation
            )
        } else {
            // Full document mode
            let docChars = min(Self.maxContextLength, docLength)
            let totalChars = docChars + 200
            return ContextEstimate(
                usedChars: totalChars,
                maxChars: Self.maxContextChars,
                mode: docLength > Self.maxContextLength ? .truncated : .fullDocument
            )
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider()

            // Content
            if aiAvailable == false {
                unavailableView
            } else if appState.selectedFile == nil {
                noFileView
            } else {
                chatContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await checkAvailability()
            // Check for initial question from Ask Pixley
            await handleInitialQuestion()
        }
        .onChange(of: appState.selectedFile) { _, _ in
            // Clear chat when file changes
            messages.removeAll()
            documentTruncated = false
            // Check for new initial question
            Task {
                await handleInitialQuestion()
            }
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

                if !messages.isEmpty {
                    Button("Forget", systemImage: "brain.head.profile.slash") {
                        clearChat()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Forget conversation (ESC)")
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Context meter - shows when there's a document
            if appState.selectedFile != nil {
                contextMeter
            }
        }
    }

    // MARK: - Context Meter

    private var contextMeter: some View {
        let estimate = contextEstimate

        return HStack(spacing: 6) {
            // Brain meter label
            Label("Memory", systemImage: "brain")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Visual gauge
            Gauge(value: estimate.percentage) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(estimate.color)
            .frame(width: 50)

            // Percentage
            Text("\(Int(estimate.percentage * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(estimate.color)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.3), value: messages.count)
    }

    private func clearChat() {
        messages.removeAll()
        documentTruncated = false
    }

    // MARK: - Unavailable View

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange)
            Text("AI Not Available")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Apple Intelligence is not available on this device")
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
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
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
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            emptyChat
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            inputArea
        }
    }

    // MARK: - Empty Chat

    private var emptyChat: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

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
                    .font(.system(size: 28))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(inputText.isEmpty || isLoading)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func checkAvailability() async {
        let availability = SystemLanguageModel.default.availability
        aiAvailable = (availability == .available)
    }

    private func handleInitialQuestion() async {
        // Pick up question from Ask Pixley on start screen
        guard let question = appState.initialChatQuestion else { return }
        appState.initialChatQuestion = nil  // Clear it so we don't repeat

        // Wait a moment for document content to load
        try? await Task.sleep(for: .milliseconds(300))

        let userMessage = ChatMessage(role: .user, content: question)
        messages.append(userMessage)
        await askAI(question)
    }

    private func sendMessage() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: question)
        messages.append(userMessage)
        inputText = ""

        Task {
            await askAI(question)
        }
    }

    /// Maximum characters to send as context (Foundation Models has ~4K token limit)
    private static let maxContextLength = 8000

    private func askAI(_ question: String) async {
        isLoading = true
        defer { isLoading = false }

        // Build chat history (excluding the message we just added)
        let priorMessages = messages.dropLast()
        let hasConversationHistory = !priorMessages.isEmpty

        // Truncate document to avoid context overflow
        let fullContent = appState.documentContent
        let context: String
        let wasTruncated = fullContent.count > Self.maxContextLength

        if wasTruncated {
            let truncated = String(fullContent.prefix(Self.maxContextLength))
            context = truncated + "\n\n[... document truncated for length ...]"
            if !documentTruncated {
                documentTruncated = true
            }
        } else {
            context = fullContent
            documentTruncated = false
        }

        do {
            let systemPrompt = """
            You are a helpful assistant analyzing a markdown document.
            Answer questions about the document concisely and accurately.
            If the answer is not in the document, say so.
            When the user asks follow-up questions about your previous responses,
            refer to the conversation history rather than re-analyzing the document.
            """

            let session = LanguageModelSession(instructions: systemPrompt)

            // Build prompt with conversation context
            var prompt: String

            if hasConversationHistory {
                // Include recent chat history for follow-up questions
                let recentHistory = priorMessages.suffix(6) // Last 3 exchanges
                let historyText = recentHistory.map { msg in
                    let role = msg.role == .user ? "User" : "Assistant"
                    return "\(role): \(msg.content)"
                }.joined(separator: "\n\n")

                prompt = """
                Document context (for reference):
                ---
                \(context.prefix(2000))...
                ---

                Previous conversation:
                \(historyText)

                User's new question: \(question)
                """
            } else {
                // First question - include full document context
                prompt = """
                Document content:
                ---
                \(context)
                ---

                Question: \(question)
                """
            }

            let response = try await session.respond(to: prompt)
            let assistantMessage = ChatMessage(role: .assistant, content: response.content)
            messages.append(assistantMessage)
        } catch {
            let errorMessage = ChatMessage(role: .assistant, content: "Sorry, I encountered an error: \(error.localizedDescription)")
            messages.append(errorMessage)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {

    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            Text(message.content)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(message.role == .user ? .white : .primary)

            if message.role == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
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

// MARK: - Context Estimate

enum ContextMode {
    case fullDocument    // First question, full doc fits
    case truncated       // First question, doc was truncated
    case conversation    // Follow-up, using chat history
}

struct ContextEstimate {
    let usedChars: Int
    let maxChars: Int
    let mode: ContextMode

    var percentage: Double {
        min(1.0, Double(usedChars) / Double(maxChars))
    }

    var usedTokensApprox: Int {
        usedChars / 4
    }

    var maxTokensApprox: Int {
        maxChars / 4
    }

    var modeLabel: String {
        switch mode {
        case .fullDocument: return "Full doc"
        case .truncated: return "Truncated"
        case .conversation: return "Chat"
        }
    }

    var modeIcon: String {
        switch mode {
        case .fullDocument: return "doc.text"
        case .truncated: return "doc.badge.ellipsis"
        case .conversation: return "bubble.left.and.bubble.right"
        }
    }

    var color: Color {
        if percentage > 0.9 {
            return .red
        } else if percentage > 0.7 {
            return .orange
        }
        return .green
    }
}
