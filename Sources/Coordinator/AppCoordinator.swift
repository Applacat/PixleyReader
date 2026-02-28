import SwiftUI
import SwiftData
import Foundation

// MARK: - App Coordinator

/// Central coordinator that owns and manages all application state.
///
/// OOD Pattern: AppCoordinator is the single source of truth for state.
/// Views observe state containers through Environment, and call coordinator
/// methods to mutate state. This provides:
/// 1. Clear ownership hierarchy
/// 2. Testable state management
/// 3. Explicit mutation paths
///
/// State is decomposed into focused containers:
/// - NavigationState: folder/file selection
/// - UIState: panel visibility, appearance
/// - DocumentState: document content, loading
@MainActor
@Observable
public final class AppCoordinator {

    // MARK: - State Containers

    /// Navigation state (folder selection, file selection)
    public let navigation = NavigationState()

    /// UI state (panel visibility, appearance)
    public let ui = UIState()

    /// Document state (content, loading, changes)
    public let document = DocumentState()


    // MARK: - Repositories

    /// File metadata repository for persistence (optional - set after container init)
    public var metadata: FileMetadataRepository?

    /// Debounced scroll save task — coalesces ~60 saves/sec into ~2/sec
    private var scrollSaveTask: Task<Void, Never>?
    private var pendingScrollPosition: (url: URL, position: Double)?

    // MARK: - Initialization

    public init() {}

    /// Initialize with a metadata repository
    public init(metadata: FileMetadataRepository) {
        self.metadata = metadata
    }

    // MARK: - Navigation Actions

    /// Opens a folder and clears previous file selection
    public func openFolder(_ url: URL) {
        navigation.openFolder(url)
        document.clearContent()
    }

    /// Closes the current folder and returns to start screen
    public func closeFolder() {
        flushScrollPosition()
        navigation.closeFolder()
        document.clearContent()
    }

    /// Selects a file for viewing
    public func selectFile(_ url: URL) {
        flushScrollPosition()
        navigation.selectFile(url)
        document.clearChanges()
    }

    /// Sets the first-launch welcome flag (auto-select first file)
    public func setFirstLaunchWelcome(_ value: Bool) {
        navigation.isFirstLaunchWelcome = value
    }

    /// Updates the sidebar filter query
    public func setSidebarFilter(_ query: String) {
        navigation.sidebarFilterQuery = query
    }

    /// Computed binding for sidebar filter query (two-way binding for TextField)
    public var sidebarFilterQuery: String {
        get { navigation.sidebarFilterQuery }
        set { navigation.sidebarFilterQuery = newValue }
    }

    /// Updates the pre-filtered display items
    func setDisplayItems(_ items: [FolderItem]) {
        navigation.displayItems = items
    }

    // MARK: - Document Actions

    /// Loads (or reloads) the document for the currently selected file
    public func loadDocument() async {
        guard let url = navigation.selectedFile else {
            document.clearContent()
            return
        }
        await document.loadFile(url: url)
        metadata?.updateLastOpened(for: url)
    }

    /// Triggers a reload of the current document
    public func reloadDocument() {
        document.triggerReload()
    }

    /// Marks the document as having external changes
    public func markDocumentChanged() {
        document.markChanged()
    }

    /// Clears the document change indicator
    public func clearDocumentChanges() {
        document.clearChanges()
    }

    // MARK: - UI Actions

    /// Toggles AI chat panel visibility
    public func toggleAIChat() {
        ui.toggleAIChat()
    }

    /// Shows an error in the status bar
    func showError(_ error: AppError) {
        ui.showError(error)
    }

    /// Dismisses the current error
    public func dismissError() {
        ui.dismissError()
    }

    /// Signals that the browser window should open
    public func requestOpenBrowser() {
        ui.shouldOpenBrowser = true
    }

    /// Consumes the browser open flag
    public func consumeOpenBrowser() {
        ui.shouldOpenBrowser = false
    }

    /// Requests sidebar collapsed on next BrowserView appear (single-file open)
    public func requestSidebarCollapsed() {
        ui.prefersSidebarCollapsed = true
    }

    /// Consumes the sidebar-collapsed flag (returns true once, then resets)
    public func consumeSidebarCollapsed() -> Bool {
        guard ui.prefersSidebarCollapsed else { return false }
        ui.prefersSidebarCollapsed = false
        return true
    }

    /// Clears the initial chat question (consumed after use)
    public func consumeInitialChatQuestion() -> String? {
        let question = ui.initialChatQuestion
        ui.initialChatQuestion = nil
        return question
    }

    /// Computed binding for AI chat visibility (two-way binding for inspector)
    public var isAIChatVisible: Bool {
        get { ui.isAIChatVisible }
        set { ui.isAIChatVisible = newValue }
    }

    // MARK: - Quick Switcher Actions

    /// Toggles the Quick Switcher overlay
    public func toggleQuickSwitcher() {
        ui.isQuickSwitcherVisible.toggle()
    }

    /// Dismisses the Quick Switcher overlay
    public func dismissQuickSwitcher() {
        ui.isQuickSwitcherVisible = false
    }

    // MARK: - Composite Actions

    /// Opens browser with a specific file selected and chat ready
    public func openWithFileContext(fileURL: URL, question: String) {
        let parentFolder = fileURL.deletingLastPathComponent()
        navigation.openFolder(parentFolder)
        navigation.selectFile(fileURL)
        ui.initialChatQuestion = question
        ui.isAIChatVisible = true
        document.clearContent()
    }

    // MARK: - Metadata Actions

    /// Saves scroll position for the currently selected file (debounced 500ms).
    /// Coalesces ~60 scroll events/sec into at most 2 disk writes/sec.
    public func saveScrollPosition(_ position: Double) {
        guard let url = navigation.selectedFile else { return }
        pendingScrollPosition = (url: url, position: position)
        scrollSaveTask?.cancel()
        scrollSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushScrollPosition()
        }
    }

    /// Flushes any pending scroll position save immediately.
    /// Call on file switch or app termination.
    public func flushScrollPosition() {
        scrollSaveTask?.cancel()
        scrollSaveTask = nil
        guard let pending = pendingScrollPosition else { return }
        pendingScrollPosition = nil
        metadata?.saveScrollPosition(pending.position, for: pending.url)
    }

    /// Gets scroll position for a file
    public func getScrollPosition(for url: URL) -> Double {
        metadata?.getMetadata(for: url)?.scrollPosition ?? 0.0
    }

    /// Toggles favorite status for a file
    public func toggleFavorite(for url: URL) {
        guard let repo = metadata else { return }
        let current = repo.isFavorite(url)
        repo.setFavorite(!current, for: url)
    }

    /// Checks if a file is favorited
    public func isFavorite(_ url: URL) -> Bool {
        metadata?.isFavorite(url) ?? false
    }

    /// Gets all favorite files
    public func getFavorites() -> [URL] {
        metadata?.getFavorites() ?? []
    }

    /// Adds a bookmark at the specified line
    public func addBookmark(lineNumber: Int, note: String? = nil) {
        guard let url = navigation.selectedFile else { return }
        metadata?.addBookmark(for: url, lineNumber: lineNumber, note: note)
    }

    /// Gets bookmarks for current file
    public func getBookmarks() -> [Bookmark] {
        guard let url = navigation.selectedFile else { return [] }
        return metadata?.getBookmarks(for: url) ?? []
    }

    /// Deletes a bookmark
    public func deleteBookmark(_ id: UUID) {
        metadata?.deleteBookmark(id)
    }
}

// MARK: - Navigation State

/// State container for folder and file navigation.
@MainActor
@Observable
public final class NavigationState {

    /// Root folder selected by user (nil until user selects one)
    public private(set) var rootFolderURL: URL? = nil

    /// Currently selected file to view
    public private(set) var selectedFile: URL? = nil

    /// Flag for first-launch welcome (auto-select first file)
    public internal(set) var isFirstLaunchWelcome: Bool = false

    /// Sidebar search/filter query
    internal var sidebarFilterQuery: String = ""

    /// Pre-filtered display items (shared with Quick Switcher)
    internal var displayItems: [FolderItem] = []

    // MARK: - Actions

    func openFolder(_ url: URL) {
        // Stop accessing previous folder if any
        rootFolderURL?.stopAccessingSecurityScopedResource()

        // Start accessing new folder's security scope
        _ = url.startAccessingSecurityScopedResource()

        rootFolderURL = url
        selectedFile = nil
        sidebarFilterQuery = ""
    }

    func closeFolder() {
        rootFolderURL?.stopAccessingSecurityScopedResource()
        rootFolderURL = nil
        selectedFile = nil
    }

    func selectFile(_ url: URL) {
        selectedFile = url
    }
}

// MARK: - UI State

/// State container for UI presentation.
@MainActor
@Observable
public final class UIState {

    /// Whether the AI Chat panel is visible
    public internal(set) var isAIChatVisible: Bool = false

    /// Flag to trigger browser window opening (consumed by views)
    public internal(set) var shouldOpenBrowser: Bool = false

    /// Initial question for chat (set from start screen, cleared after use)
    public internal(set) var initialChatQuestion: String? = nil

    /// Current error to display in the status bar
    private(set) var currentError: AppError? = nil

    /// Color scheme override for the session (nil = follow system)
    public internal(set) var colorSchemeOverride: ColorScheme? = nil

    /// Whether the Quick Switcher overlay is visible
    public internal(set) var isQuickSwitcherVisible: Bool = false

    /// Consume-once flag: sidebar should start collapsed (single-file open)
    public internal(set) var prefersSidebarCollapsed: Bool = false

    // MARK: - Actions

    func toggleAIChat() {
        isAIChatVisible.toggle()
    }

    func showError(_ error: AppError) {
        currentError = error
    }

    func dismissError() {
        currentError = nil
    }
}

// MARK: - Document State

/// State container for document content and loading.
/// DocumentState is the single source of truth for document text.
/// It owns file loading — views read from it, never load independently.
@MainActor
@Observable
public final class DocumentState {

    /// Current document content (loaded from file)
    public private(set) var content: String = ""

    /// Whether the document is currently loading
    public private(set) var isLoading: Bool = false

    /// File load error message (nil = no error)
    public private(set) var errorMessage: String? = nil

    /// Whether the current file has unseen external changes
    public private(set) var hasChanges: Bool = false

    /// Reload trigger (incremented to force reload)
    public private(set) var reloadTrigger: Int = 0

    // MARK: - File Loading

    /// Loads file content from disk. This is the authoritative load path.
    /// MarkdownView and ChatView both read from `content` after this completes.
    func loadFile(url: URL) async {
        isLoading = true
        errorMessage = nil

        do {
            let text = try await Task.detached(priority: .userInitiated) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int ?? 0

                guard fileSize <= MarkdownConfig.maxTextSize else {
                    throw FileLoadError.fileTooLarge(size: fileSize)
                }

                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw FileLoadError.invalidEncoding
                }
                return text
            }.value

            content = text
            hasChanges = false
        } catch {
            errorMessage = error.localizedDescription
            content = ""
        }

        isLoading = false
    }

    // MARK: - Actions

    func clearContent() {
        content = ""
        hasChanges = false
        errorMessage = nil
    }

    func markChanged() {
        hasChanges = true
    }

    func clearChanges() {
        hasChanges = false
    }

    func triggerReload() {
        reloadTrigger += 1
        hasChanges = false
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

// MARK: - Environment Key

/// Environment key for injecting AppCoordinator into the view hierarchy.
/// The shared instance provides a default for views that don't have a coordinator injected.
/// In practice, the app always injects a coordinator explicitly via .environment(\.coordinator, coordinator).
// @preconcurrency required: EnvironmentKey.defaultValue lacks @MainActor annotation.
// Safe because SwiftUI accesses this on @MainActor view update path.
private struct AppCoordinatorKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = AppCoordinator()
}

extension EnvironmentValues {
    public var coordinator: AppCoordinator {
        get { self[AppCoordinatorKey.self] }
        set { self[AppCoordinatorKey.self] = newValue }
    }
}
