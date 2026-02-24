import SwiftUI
import AppKit

// MARK: - File Load Trigger

/// Combines file selection and reload trigger into a single equatable value.
/// Used with `.task(id:)` to avoid race conditions from separate task modifiers.
private struct FileLoadTrigger: Equatable {
    let file: URL?
    let reload: Int
}

// MARK: - Markdown View

/// The center panel displaying markdown content with syntax highlighting.
/// Reads document content from DocumentState (the single source of truth).
struct MarkdownView: View {

    @Environment(\.coordinator) private var coordinator

    @State private var pendingScrollPosition: Double? = nil
    @State private var fileWatcher: FileWatcher? = nil
    @State private var readingProgress: Double = 0
    @State private var bookmarkedLines: Set<Int> = []

    // MARK: - Body

    var body: some View {
        ZStack {
            if coordinator.navigation.selectedFile == nil {
                emptyState
            } else if coordinator.document.isLoading {
                loadingView
            } else if let error = coordinator.document.errorMessage {
                errorView(error)
            } else {
                markdownContent
            }

            // Reload pill overlay
            if coordinator.document.hasChanges {
                VStack {
                    Spacer()
                    ReloadPill {
                        coordinator.reloadDocument()
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task(id: FileLoadTrigger(file: coordinator.navigation.selectedFile, reload: coordinator.document.reloadTrigger)) {
            await loadFile()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
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
        MarkdownEditor(
            text: .constant(coordinator.document.content),
            onError: { error in coordinator.showError(error) },
            onScrollPositionChanged: { position in
                readingProgress = position
                coordinator.saveScrollPosition(position)
            },
            restoreScrollPosition: pendingScrollPosition,
            bookmarkedLines: bookmarkedLines,
            onToggleBookmark: { lineNumber in
                toggleBookmark(at: lineNumber)
            }
        )
        .overlay(alignment: .topTrailing) {
            if coordinator.navigation.selectedFile != nil {
                ReadingProgressBadge(progress: readingProgress)
                    .padding(8)
            }
        }
    }

    // MARK: - Load File

    /// Delegates file loading to DocumentState (the single source of truth).
    /// MarkdownView handles view-level concerns: scroll restoration, bookmarks, file watching.
    private func loadFile() async {
        guard let fileURL = coordinator.navigation.selectedFile else {
            pendingScrollPosition = nil
            return
        }

        // Look up saved scroll position before loading
        let savedPosition = coordinator.getScrollPosition(for: fileURL)

        // Delegate loading to coordinator (DocumentState owns the content)
        await coordinator.loadDocument()

        // View-level concerns after successful load
        if coordinator.document.errorMessage == nil {
            pendingScrollPosition = savedPosition > 0 ? savedPosition : nil
            refreshBookmarks()
            startWatching(fileURL)
        }
    }

    // MARK: - Bookmarks

    private func toggleBookmark(at lineNumber: Int) {
        let existing = coordinator.getBookmarks()
        if let bookmark = existing.first(where: { $0.lineNumber == lineNumber }) {
            coordinator.deleteBookmark(bookmark.id)
        } else {
            coordinator.addBookmark(lineNumber: lineNumber)
        }
        // Fetch bookmarks once after mutation (avoids double-fetch via refreshBookmarks)
        let updated = coordinator.getBookmarks()
        bookmarkedLines = Set(updated.map(\.lineNumber))
    }

    private func refreshBookmarks() {
        let bookmarks = coordinator.getBookmarks()
        bookmarkedLines = Set(bookmarks.map(\.lineNumber))
    }

    // MARK: - File Watching

    private func startWatching(_ url: URL) {
        if fileWatcher == nil {
            fileWatcher = FileWatcher { [weak coordinator] in
                coordinator?.markDocumentChanged()
            }
        }
        fileWatcher?.watch(url)
    }
}

// MARK: - Reload Pill

/// Floating pill showing "Content updated" with a Reload button.
struct ReloadPill: View {

    let onReload: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.callout.weight(.medium))
                .accessibilityHidden(true)

            Text("Content updated")
                .font(.callout.weight(.medium))

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
        .animation(
            reduceMotion
                ? .none
                : .spring(response: 0.4, dampingFraction: 0.8),
            value: true
        )
    }
}

// MARK: - Reading Progress Badge

/// Small progress badge showing scroll percentage in top-right corner.
struct ReadingProgressBadge: View {
    let progress: Double

    var body: some View {
        Text("\(Int(progress * 100))%")
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
    }
}
