import SwiftUI

// MARK: - File Load Trigger

/// Combines file selection and reload trigger into a single equatable value.
/// Used with `.task(id:)` to avoid race conditions from separate task modifiers.
private struct FileLoadTrigger: Equatable {
    let file: URL?
    let reload: Int
}

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
        .task(id: FileLoadTrigger(file: appState.selectedFile, reload: appState.reloadTrigger)) {
            await loadFile()
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
        MarkdownEditor(text: .constant(content), onError: { error in
            appState.showError(error)
        })
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
            // Move file I/O to background thread to avoid blocking main thread
            let text = try await Task.detached(priority: .userInitiated) {
                // Security: Check file size before loading to prevent DoS
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? Int ?? 0
                
                guard fileSize <= MarkdownConfig.maxTextSize else {
                    throw FileLoadError.fileTooLarge(size: fileSize)
                }
                
                let data = try Data(contentsOf: fileURL)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw FileLoadError.invalidEncoding
                }
                return text
            }.value

            content = text
            appState.documentContent = text

            // Notify any waiters that document has loaded
            appState.onDocumentLoaded?()
            appState.onDocumentLoaded = nil  // Clear after calling
        } catch let error as FileLoadError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - File Load Errors

enum FileLoadError: LocalizedError {
    case fileTooLarge(size: Int)
    case invalidEncoding
    
    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            let mb = Double(size) / 1_048_576
            return "File is too large (\(String(format: "%.1f", mb)) MB). Maximum supported size is 10 MB."
        case .invalidEncoding:
            return "Unable to decode file as UTF-8 text"
        }
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
