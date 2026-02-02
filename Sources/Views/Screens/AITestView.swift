import SwiftUI
import FoundationModels

// MARK: - Folder Action Contract

/// Contract: The AI must output one of these folder actions.
/// This is the OOD "contract" that structured generation must fulfill.
@Generable(description: "A folder navigation action based on user request")
struct FolderActionContract {
    @Guide(description: "The type of folder to open")
    @Guide(.anyOf(["home", "documents", "downloads", "custom"]))
    let action: String

    @Guide(description: "The custom path if action is 'custom', otherwise empty string")
    let customPath: String
}

// MARK: - AI Test View

/// Test view for experimenting with Apple Foundation Models.
/// Tests both simple generation and contract-based structured output.
struct AITestView: View {

    // Increment test state
    @State private var currentNumber: Int = 0

    // Contract test state
    @State private var userPrompt: String = "open my documents"
    @State private var contractResult: FolderActionContract?

    // Shared state
    @State private var aiResponse: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // MARK: - Increment Test
                incrementTestSection

                Divider()

                // MARK: - Contract Test
                contractTestSection
            }
            .padding(40)
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: - Increment Test Section

    private var incrementTestSection: some View {
        VStack(spacing: 16) {
            Text("Test 1: Simple Generation")
                .font(.title2)
                .fontWeight(.bold)

            Text("\(currentNumber)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)

            Button {
                Task { await askAIToIncrement() }
            } label: {
                HStack {
                    if isLoading { ProgressView().scaleEffect(0.8) }
                    Text(isLoading ? "Thinking..." : "Ask AI to Increment")
                }
                .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
    }

    // MARK: - Contract Test Section

    private var contractTestSection: some View {
        VStack(spacing: 16) {
            Text("Test 2: Contract Fulfillment")
                .font(.title2)
                .fontWeight(.bold)

            Text("Test if AI correctly identifies folder action from natural language")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Prompt input
            TextField("Enter prompt...", text: $userPrompt)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)

            // Quick test buttons
            HStack(spacing: 8) {
                ForEach(["open my documents", "go to home", "open downloads", "open /Users/test/Code"], id: \.self) { prompt in
                    Button(prompt) {
                        userPrompt = prompt
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            // Test button
            Button {
                Task { await testContract() }
            } label: {
                HStack {
                    if isLoading { ProgressView().scaleEffect(0.8) }
                    Text(isLoading ? "Testing..." : "Test Contract")
                }
                .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            // Result display
            if let result = contractResult {
                VStack(spacing: 8) {
                    Text("Contract Result:")
                        .font(.headline)

                    HStack(spacing: 20) {
                        VStack {
                            Text("action")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.action)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(colorForAction(result.action))
                        }

                        if !result.customPath.isEmpty {
                            VStack {
                                Text("customPath")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(result.customPath)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            // Response/Error display
            if !aiResponse.isEmpty {
                Text(aiResponse)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(4)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func colorForAction(_ action: String) -> Color {
        switch action {
        case "home": return .blue
        case "documents": return .green
        case "downloads": return .orange
        case "custom": return .purple
        default: return .gray
        }
    }

    // MARK: - AI Interaction

    private func askAIToIncrement() async {
        isLoading = true
        errorMessage = nil

        do {
            // Check availability
            let availability = SystemLanguageModel.default.availability
            print("🤖 [AI Test] Availability: \(availability)")

            guard availability == .available else {
                let msg = "AI not available: \(availability)"
                print("🤖 [AI Test] \(msg)")
                errorMessage = msg
                isLoading = false
                return
            }

            // Create session and ask
            let session = LanguageModelSession()
            let prompt = """
                The current number is \(currentNumber).
                What is \(currentNumber) + 1?
                Reply with ONLY the number, nothing else.
                """

            print("🤖 [AI Test] Sending prompt: \(prompt)")

            let response = try await session.respond(to: prompt)
            let responseText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            print("🤖 [AI Test] Raw response: '\(responseText)'")
            print("🤖 [AI Test] Full response object: \(response)")

            // Try to parse the number
            if let newNumber = Int(responseText) {
                currentNumber = newNumber
                aiResponse = "AI said: \(responseText)"
                print("🤖 [AI Test] Parsed number: \(newNumber)")
            } else {
                // AI gave a non-numeric response, show it
                aiResponse = "AI response: \(responseText)"
                print("🤖 [AI Test] Non-numeric response, trying to extract...")
                // Try to extract number from response
                let numbers = responseText.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }
                if let firstNumber = numbers.first {
                    currentNumber = firstNumber
                    print("🤖 [AI Test] Extracted number: \(firstNumber)")
                }
            }
        } catch {
            let msg = "Error: \(error.localizedDescription)"
            print("🤖 [AI Test] ERROR: \(error)")
            errorMessage = msg
        }

        isLoading = false
    }

    // MARK: - Contract Test

    private func testContract() async {
        isLoading = true
        errorMessage = nil
        aiResponse = ""
        contractResult = nil

        do {
            let availability = SystemLanguageModel.default.availability
            print("🤖 [Contract Test] Availability: \(availability)")

            guard availability == .available else {
                errorMessage = "AI not available: \(availability)"
                isLoading = false
                return
            }

            let session = LanguageModelSession(
                instructions: """
                    You help users navigate to folders. Based on the user's request,
                    determine which folder action to take:
                    - "home" for home folder requests
                    - "documents" for documents folder requests
                    - "downloads" for downloads folder requests
                    - "custom" for specific paths (put the path in customPath)

                    If unsure, default to "documents".
                    For custom paths, extract the path from the user's request.
                    """
            )

            print("🤖 [Contract Test] Prompt: '\(userPrompt)'")

            let response = try await session.respond(
                to: userPrompt,
                generating: FolderActionContract.self
            )

            // Response wraps the content - extract it
            let result = response.content

            print("🤖 [Contract Test] Response object: \(response)")
            print("🤖 [Contract Test] Content: \(result)")
            print("🤖 [Contract Test] Action: \(result.action)")
            print("🤖 [Contract Test] CustomPath: \(result.customPath)")

            contractResult = result
            aiResponse = "Contract fulfilled successfully"

        } catch {
            print("🤖 [Contract Test] ERROR: \(error)")
            errorMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
