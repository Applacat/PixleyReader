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
    @State private var isCheckingAvailability = true
    @State private var documentTruncated = false
    @State private var isWaitingForDocument = false

    // Service for business logic (testable)
    private let chatService = ChatService()

    /// Estimated context usage for the next request (delegated to service)
    private var contextEstimate: ContextEstimate {
        chatService.estimateContext(
            documentLength: appState.documentContent.count,
            messages: messages
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider()

            // Content
            if isCheckingAvailability {
                checkingAvailabilityView
            } else if aiAvailable == false {
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
        }
        .task(id: appState.initialChatQuestion) {
            // Only handle initial question when it's set from the start screen
            // Don't clear chat on file changes - that's manual only via "Forget" button
            if appState.initialChatQuestion != nil {
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
                
                // Show warning when approaching message limit
                if messages.count > ChatConfiguration.maxMessageHistory * 3 / 4 {
                    Text("\(messages.count)/\(ChatConfiguration.maxMessageHistory)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

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

        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                // Brain meter label
                Label("Memory", systemImage: "brain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Visual gauge
                Gauge(value: estimate.percentage) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(meterColor(for: estimate))
                .frame(width: 50)

                // Percentage
                Text("\(Int(estimate.percentage * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(meterColor(for: estimate))
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            
            // Document truncation warning
            if documentTruncated {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Document truncated to fit context")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.3), value: messages.count)
    }

    private func meterColor(for estimate: ContextEstimate) -> Color {
        if estimate.isHighUsage {
            return .red
        } else if estimate.isMediumUsage {
            return .orange
        }
        return .green
    }

    private func clearChat() {
        messages.removeAll()
        documentTruncated = false
    }

    // MARK: - Checking Availability View

    private var checkingAvailabilityView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Checking AI Availability...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Unavailable View

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange)
            Text("AI Chat Unavailable")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            // User-friendly availability messaging
            availabilityMessage
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private var availabilityMessage: some View {
        let availability = SystemLanguageModel.default.availability
        
        switch availability {
        case .unavailable(.deviceNotEligible):
            Text("AI features require a Mac with Apple Silicon (M1 or later)")
        case .unavailable(.appleIntelligenceNotEnabled):
            VStack(spacing: 8) {
                Text("Apple Intelligence is not enabled")
                Text("To enable: System Settings > Apple Intelligence & Siri")
                    .font(.caption2)
            }
        case .unavailable(.modelNotReady):
            Text("AI model is downloading. Please try again later.")
        default:
            Text("AI features are currently unavailable")
        }
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
        isCheckingAvailability = true
        aiAvailable = chatService.checkAvailability()
        isCheckingAvailability = false
    }

    /// Handle initial question from start screen feature
    /// Waits for document content to be loaded before sending question
    private func handleInitialQuestion() async {
        // Pick up question from start screen
        guard let question = appState.initialChatQuestion else { return }
        appState.initialChatQuestion = nil  // Clear it so we don't repeat

        isWaitingForDocument = true
        defer { isWaitingForDocument = false }

        // Wait for document content using ChatService's structured concurrency helper
        let result = await chatService.waitForDocument(
            isCurrentlyEmpty: appState.documentContent.isEmpty,
            setLoadCallback: { callback in
                appState.onDocumentLoaded = callback
            },
            clearLoadCallback: {
                appState.onDocumentLoaded = nil
            }
        )

        // Handle timeout or still-empty document
        if result == .timeout || appState.documentContent.isEmpty {
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Unable to load the document. Please try selecting it again from the sidebar."
            )
            messages.append(errorMessage)
            return
        }

        let userMessage = ChatMessage(role: .user, content: question)
        messages.append(userMessage)
        await askAI(question)
    }

    @MainActor
    private func sendMessage() {
        // Validate input using the validator
        switch ChatInputValidator.validate(inputText) {
        case .failure(.empty):
            return  // Silent return for empty input
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

            // Limit message history to prevent unbounded memory growth
            messages = ChatInputValidator.trimHistory(messages, max: ChatConfiguration.maxMessageHistory)

            inputText = ""

            Task {
                await askAI(question)
            }
        }
    }

    @MainActor
    private func askAI(_ question: String) async {
        isLoading = true
        defer { isLoading = false }

        // Build chat history (excluding the message we just added)
        let priorMessages = Array(messages.dropLast())

        // Check if document was truncated (for UI state)
        let (_, wasTruncated) = chatService.truncateDocument(appState.documentContent)
        documentTruncated = wasTruncated

        do {
            let response = try await chatService.askAI(
                question: question,
                documentContent: appState.documentContent,
                priorMessages: priorMessages
            )
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMessage)
            
            // Limit message history after AI response as well
            if messages.count > ChatConfiguration.maxMessageHistory {
                messages = Array(messages.suffix(ChatConfiguration.maxMessageHistory))
            }
        } catch {
            // Create user-friendly error messages
            let errorContent: String
            
            if let sessionError = error as? LanguageModelSession.GenerationError {
                switch sessionError {
                case .exceededContextWindowSize:
                    errorContent = "The document is too long for me to process in one conversation. Try asking about specific sections, or start a new chat to reset my memory."
                default:
                    errorContent = "I encountered an error while thinking. Please try asking your question again."
                }
            } else {
                errorContent = "I encountered an error: \(error.localizedDescription)\n\nPlease try your question again."
            }
            
            let errorMessage = ChatMessage(
                role: .assistant, 
                content: errorContent
            )
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
