import SwiftUI

// MARK: - Markdown View

/// The center panel displaying markdown content with syntax highlighting.
struct MarkdownView: View {

    @Environment(AppState.self) private var appState

    @State private var content: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        ZStack {
            if appState.selectedFile == nil {
                emptyState
            } else if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                markdownContent
            }

            // Reload pill overlay
            if appState.fileHasChanges {
                VStack {
                    Spacer()
                    ReloadPill {
                        appState.triggerReload()
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task(id: appState.selectedFile) {
            await loadFile()
        }
        .task(id: appState.reloadTrigger) {
            if appState.reloadTrigger > 0 {
                await loadFile()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select a file to view")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose a markdown file from the sidebar")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading...")
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
            Text("Error loading file")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Markdown Content

    private var markdownContent: some View {
        MarkdownEditor(text: .constant(content))
    }

    // MARK: - Load File

    private func loadFile() async {
        guard let fileURL = appState.selectedFile else {
            content = ""
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let data = try Data(contentsOf: fileURL)
            if let text = String(data: data, encoding: .utf8) {
                content = text
                appState.documentContent = text
            } else {
                errorMessage = "Unable to decode file as text"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Reload Pill

/// Floating pill showing "Content updated" with a Reload button.
struct ReloadPill: View {

    let onReload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))

            Text("Content updated")
                .font(.system(size: 13, weight: .medium))

            Button("Reload") {
                onReload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: true)
    }
}
