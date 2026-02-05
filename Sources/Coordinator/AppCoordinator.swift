import SwiftUI
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

    // MARK: - Initialization

    public init() {}

    // MARK: - Navigation Actions

    /// Opens a folder and clears previous file selection
    public func openFolder(_ url: URL) {
        navigation.openFolder(url)
        document.clearContent()
    }

    /// Closes the current folder and returns to start screen
    public func closeFolder() {
        navigation.closeFolder()
        document.clearContent()
    }

    /// Selects a file for viewing
    public func selectFile(_ url: URL) {
        navigation.selectFile(url)
        document.clearChanges()
    }

    // MARK: - Document Actions

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

    /// Updates document content after loading
    public func setDocumentContent(_ content: String) {
        document.setContent(content)
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
}

// MARK: - Navigation State

/// State container for folder and file navigation.
@MainActor
@Observable
public final class NavigationState {

    /// Root folder selected by user (nil until user selects one)
    public var rootFolderURL: URL? = nil

    /// Currently selected file to view
    public var selectedFile: URL? = nil

    /// Flag for first-launch welcome (auto-select first file)
    public var isFirstLaunchWelcome: Bool = false

    // MARK: - Actions

    func openFolder(_ url: URL) {
        // Stop accessing previous folder if any
        rootFolderURL?.stopAccessingSecurityScopedResource()

        // Start accessing new folder's security scope
        _ = url.startAccessingSecurityScopedResource()

        rootFolderURL = url
        selectedFile = nil
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
    public var isAIChatVisible: Bool = false

    /// Flag to trigger browser window opening (consumed by views)
    public var shouldOpenBrowser: Bool = false

    /// Initial question for chat (set from start screen, cleared after use)
    public var initialChatQuestion: String? = nil

    /// Current error to display in the status bar
    var currentError: AppError? = nil

    /// Color scheme override for the session (nil = follow system)
    public var colorSchemeOverride: ColorScheme? = nil

    // MARK: - Actions

    func toggleAIChat() {
        isAIChatVisible.toggle()
    }

    func showError(_ error: AppError) {
        currentError = error

        // Auto-dismiss after 5 seconds
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if self?.currentError == error {
                self?.currentError = nil
            }
        }
    }

    func dismissError() {
        currentError = nil
    }
}

// MARK: - Document State

/// State container for document content and loading.
@MainActor
@Observable
public final class DocumentState {

    /// Current document content (loaded from file)
    public var content: String = ""

    /// Whether the current file has unseen external changes
    public var hasChanges: Bool = false

    /// Reload trigger (incremented to force reload)
    public var reloadTrigger: Int = 0

    /// Callback for when document finishes loading
    public var onLoaded: (@MainActor () -> Void)? = nil

    // MARK: - Actions

    func setContent(_ newContent: String) {
        content = newContent
        hasChanges = false
    }

    func clearContent() {
        content = ""
        hasChanges = false
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
