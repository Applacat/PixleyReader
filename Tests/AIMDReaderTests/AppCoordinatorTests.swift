import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// Since AppCoordinator and its state containers are in the main app (executable target),
// we mirror the implementation here for testing state transition logic.

// MARK: - TestableNavigationState

@MainActor
private final class TestableNavigationState {
    private(set) var rootFolderURL: URL? = nil
    private(set) var selectedFile: URL? = nil
    var isFirstLaunchWelcome: Bool = false
    var sidebarFilterQuery: String = ""

    func openFolder(_ url: URL) {
        rootFolderURL = url
        selectedFile = nil
        sidebarFilterQuery = ""
    }

    func closeFolder() {
        rootFolderURL = nil
        selectedFile = nil
    }

    func selectFile(_ url: URL) {
        selectedFile = url
    }
}

// MARK: - TestableUIState

@MainActor
private final class TestableUIState {
    var isAIChatVisible: Bool = false
    var shouldOpenBrowser: Bool = false
    var initialChatQuestion: String? = nil
    private(set) var currentError: TestableAppError? = nil
    var isQuickSwitcherVisible: Bool = false

    func toggleAIChat() {
        isAIChatVisible.toggle()
    }

    func showError(_ error: TestableAppError) {
        currentError = error
    }

    func dismissError() {
        currentError = nil
    }
}

// MARK: - TestableAppError (for UI state tests)

private enum TestableAppError: Equatable {
    case warning(message: String)
    case error(message: String)

    var message: String {
        switch self {
        case .warning(let message), .error(let message):
            return message
        }
    }

    var isWarning: Bool {
        switch self {
        case .warning: return true
        case .error: return false
        }
    }
}

// MARK: - TestableDocumentState

@MainActor
private final class TestableDocumentState {
    private(set) var content: String = ""
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String? = nil
    private(set) var hasChanges: Bool = false
    private(set) var reloadTrigger: Int = 0

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

// MARK: - Mock FileMetadataRepository

@MainActor
private final class MockMetadataRepository {
    var scrollPositions: [String: Double] = [:]
    var favorites: Set<String> = []
    var lastOpenedDates: [String: Date] = [:]

    func saveScrollPosition(_ position: Double, for url: URL) {
        scrollPositions[url.path] = position
    }

    func getScrollPosition(for url: URL) -> Double {
        scrollPositions[url.path] ?? 0.0
    }

    func setFavorite(_ isFavorite: Bool, for url: URL) {
        if isFavorite {
            favorites.insert(url.path)
        } else {
            favorites.remove(url.path)
        }
    }

    func isFavorite(_ url: URL) -> Bool {
        favorites.contains(url.path)
    }

    func getFavorites() -> [URL] {
        favorites.map { URL(fileURLWithPath: $0) }
    }

    func updateLastOpened(for url: URL) {
        lastOpenedDates[url.path] = Date()
    }
}

// MARK: - TestableAppCoordinator

@MainActor
private final class TestableAppCoordinator {
    let navigation = TestableNavigationState()
    let ui = TestableUIState()
    let document = TestableDocumentState()
    var metadata: MockMetadataRepository?

    private var pendingScrollPosition: (url: URL, position: Double)?

    init(metadata: MockMetadataRepository? = nil) {
        self.metadata = metadata
    }

    func openFolder(_ url: URL) {
        navigation.openFolder(url)
        document.clearContent()
    }

    func closeFolder() {
        flushScrollPosition()
        navigation.closeFolder()
        document.clearContent()
    }

    func selectFile(_ url: URL) {
        flushScrollPosition()
        navigation.selectFile(url)
        document.clearChanges()
    }

    func openWithFileContext(fileURL: URL, question: String) {
        let parentFolder = fileURL.deletingLastPathComponent()
        navigation.openFolder(parentFolder)
        navigation.selectFile(fileURL)
        ui.initialChatQuestion = question
        ui.isAIChatVisible = true
        document.clearContent()
    }

    func consumeInitialChatQuestion() -> String? {
        let question = ui.initialChatQuestion
        ui.initialChatQuestion = nil
        return question
    }

    func saveScrollPosition(_ position: Double) {
        guard let url = navigation.selectedFile else { return }
        pendingScrollPosition = (url: url, position: position)
    }

    func flushScrollPosition() {
        guard let pending = pendingScrollPosition else { return }
        pendingScrollPosition = nil
        metadata?.saveScrollPosition(pending.position, for: pending.url)
    }

    func toggleFavorite(for url: URL) {
        guard let repo = metadata else { return }
        let current = repo.isFavorite(url)
        repo.setFavorite(!current, for: url)
    }

    func isFavorite(_ url: URL) -> Bool {
        metadata?.isFavorite(url) ?? false
    }
}

// MARK: - FileLoadError Mirror

private enum TestableFileLoadError: LocalizedError {
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

// MARK: - NavigationState Tests

final class NavigationStateTests: XCTestCase {

    @MainActor
    func testOpenFolder_setsRootFolderURL() {
        let nav = TestableNavigationState()
        let url = URL(fileURLWithPath: "/tmp/testfolder")
        nav.openFolder(url)
        XCTAssertEqual(nav.rootFolderURL, url)
    }

    @MainActor
    func testOpenFolder_clearsSelectedFile() {
        let nav = TestableNavigationState()
        nav.selectFile(URL(fileURLWithPath: "/tmp/test.md"))
        nav.openFolder(URL(fileURLWithPath: "/tmp/testfolder"))
        XCTAssertNil(nav.selectedFile)
    }

    @MainActor
    func testOpenFolder_clearsSidebarFilterQuery() {
        let nav = TestableNavigationState()
        nav.sidebarFilterQuery = "search query"
        nav.openFolder(URL(fileURLWithPath: "/tmp/testfolder"))
        XCTAssertEqual(nav.sidebarFilterQuery, "")
    }

    @MainActor
    func testCloseFolder_nilsRootFolderURL() {
        let nav = TestableNavigationState()
        nav.openFolder(URL(fileURLWithPath: "/tmp/testfolder"))
        nav.closeFolder()
        XCTAssertNil(nav.rootFolderURL)
    }

    @MainActor
    func testCloseFolder_nilsSelectedFile() {
        let nav = TestableNavigationState()
        nav.openFolder(URL(fileURLWithPath: "/tmp/testfolder"))
        nav.selectFile(URL(fileURLWithPath: "/tmp/test.md"))
        nav.closeFolder()
        XCTAssertNil(nav.selectedFile)
    }

    @MainActor
    func testSelectFile_setsSelectedFile() {
        let nav = TestableNavigationState()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        nav.selectFile(url)
        XCTAssertEqual(nav.selectedFile, url)
    }

    @MainActor
    func testOpenNewFolder_clearsPreviousSelection() {
        let nav = TestableNavigationState()
        nav.openFolder(URL(fileURLWithPath: "/tmp/folder1"))
        nav.selectFile(URL(fileURLWithPath: "/tmp/folder1/file.md"))
        XCTAssertNotNil(nav.selectedFile)

        nav.openFolder(URL(fileURLWithPath: "/tmp/folder2"))
        XCTAssertNil(nav.selectedFile)
        XCTAssertEqual(nav.rootFolderURL?.lastPathComponent, "folder2")
    }
}

// MARK: - UIState Tests

final class UIStateTests: XCTestCase {

    @MainActor
    func testToggleAIChat_flipsVisibility() {
        let ui = TestableUIState()
        XCTAssertFalse(ui.isAIChatVisible)
        ui.toggleAIChat()
        XCTAssertTrue(ui.isAIChatVisible)
        ui.toggleAIChat()
        XCTAssertFalse(ui.isAIChatVisible)
    }

    @MainActor
    func testShowError_setsCurrentError() {
        let ui = TestableUIState()
        ui.showError(.error(message: "test"))
        XCTAssertEqual(ui.currentError?.message, "test")
    }

    @MainActor
    func testDismissError_clearsCurrentError() {
        let ui = TestableUIState()
        ui.showError(.error(message: "test"))
        ui.dismissError()
        XCTAssertNil(ui.currentError)
    }

    @MainActor
    func testShouldOpenBrowser_setAndConsumed() {
        let ui = TestableUIState()
        XCTAssertFalse(ui.shouldOpenBrowser)
        ui.shouldOpenBrowser = true
        XCTAssertTrue(ui.shouldOpenBrowser)
        ui.shouldOpenBrowser = false
        XCTAssertFalse(ui.shouldOpenBrowser)
    }

    @MainActor
    func testInitialChatQuestion_setAndConsumed() {
        let ui = TestableUIState()
        XCTAssertNil(ui.initialChatQuestion)
        ui.initialChatQuestion = "What does this do?"
        XCTAssertEqual(ui.initialChatQuestion, "What does this do?")
        // Consume
        let question = ui.initialChatQuestion
        ui.initialChatQuestion = nil
        XCTAssertEqual(question, "What does this do?")
        XCTAssertNil(ui.initialChatQuestion)
    }

    @MainActor
    func testIsQuickSwitcherVisible_toggles() {
        let ui = TestableUIState()
        XCTAssertFalse(ui.isQuickSwitcherVisible)
        ui.isQuickSwitcherVisible.toggle()
        XCTAssertTrue(ui.isQuickSwitcherVisible)
        ui.isQuickSwitcherVisible.toggle()
        XCTAssertFalse(ui.isQuickSwitcherVisible)
    }
}

// MARK: - DocumentState Tests

final class DocumentStateTests: XCTestCase {

    @MainActor
    func testClearContent_resetsAll() {
        let doc = TestableDocumentState()
        doc.markChanged()
        doc.clearContent()
        XCTAssertEqual(doc.content, "")
        XCTAssertFalse(doc.hasChanges)
        XCTAssertNil(doc.errorMessage)
    }

    @MainActor
    func testMarkChanged_setsHasChanges() {
        let doc = TestableDocumentState()
        XCTAssertFalse(doc.hasChanges)
        doc.markChanged()
        XCTAssertTrue(doc.hasChanges)
    }

    @MainActor
    func testClearChanges_resetsHasChanges() {
        let doc = TestableDocumentState()
        doc.markChanged()
        XCTAssertTrue(doc.hasChanges)
        doc.clearChanges()
        XCTAssertFalse(doc.hasChanges)
    }

    @MainActor
    func testTriggerReload_incrementsReloadTrigger() {
        let doc = TestableDocumentState()
        XCTAssertEqual(doc.reloadTrigger, 0)
        doc.triggerReload()
        XCTAssertEqual(doc.reloadTrigger, 1)
        doc.triggerReload()
        XCTAssertEqual(doc.reloadTrigger, 2)
    }

    @MainActor
    func testTriggerReload_clearsHasChanges() {
        let doc = TestableDocumentState()
        doc.markChanged()
        XCTAssertTrue(doc.hasChanges)
        doc.triggerReload()
        XCTAssertFalse(doc.hasChanges)
    }
}

// MARK: - AppCoordinator Composite Tests

final class AppCoordinatorTests: XCTestCase {

    @MainActor
    func testOpenFolder_delegatesToNavAndClearsDocument() {
        let coordinator = TestableAppCoordinator()
        coordinator.document.markChanged()

        let url = URL(fileURLWithPath: "/tmp/testfolder")
        coordinator.openFolder(url)

        XCTAssertEqual(coordinator.navigation.rootFolderURL, url)
        XCTAssertEqual(coordinator.document.content, "")
        XCTAssertFalse(coordinator.document.hasChanges)
    }

    @MainActor
    func testCloseFolder_delegatesToNavAndClearsDocument() {
        let coordinator = TestableAppCoordinator()
        coordinator.openFolder(URL(fileURLWithPath: "/tmp/testfolder"))
        coordinator.document.markChanged()

        coordinator.closeFolder()

        XCTAssertNil(coordinator.navigation.rootFolderURL)
        XCTAssertEqual(coordinator.document.content, "")
        XCTAssertFalse(coordinator.document.hasChanges)
    }

    @MainActor
    func testSelectFile_flushesScrollAndDelegatesToNav() {
        let metadata = MockMetadataRepository()
        let coordinator = TestableAppCoordinator(metadata: metadata)

        let folder = URL(fileURLWithPath: "/tmp/testfolder")
        coordinator.openFolder(folder)

        let file1 = URL(fileURLWithPath: "/tmp/testfolder/file1.md")
        coordinator.selectFile(file1)
        coordinator.saveScrollPosition(0.5)

        let file2 = URL(fileURLWithPath: "/tmp/testfolder/file2.md")
        coordinator.selectFile(file2)

        // Scroll position for file1 should have been flushed
        XCTAssertEqual(metadata.scrollPositions[file1.path], 0.5)
        XCTAssertEqual(coordinator.navigation.selectedFile, file2)
    }

    @MainActor
    func testSelectFile_clearsChanges() {
        let coordinator = TestableAppCoordinator()
        coordinator.document.markChanged()
        XCTAssertTrue(coordinator.document.hasChanges)

        coordinator.selectFile(URL(fileURLWithPath: "/tmp/test.md"))
        XCTAssertFalse(coordinator.document.hasChanges)
    }

    @MainActor
    func testOpenWithFileContext_setsAllState() {
        let coordinator = TestableAppCoordinator()
        let fileURL = URL(fileURLWithPath: "/tmp/testfolder/readme.md")

        coordinator.openWithFileContext(fileURL: fileURL, question: "What is this?")

        // Should set folder to parent
        XCTAssertEqual(coordinator.navigation.rootFolderURL?.lastPathComponent, "testfolder")
        // Should select the file
        XCTAssertEqual(coordinator.navigation.selectedFile, fileURL)
        // Should set chat question
        XCTAssertEqual(coordinator.ui.initialChatQuestion, "What is this?")
        // Should show AI chat
        XCTAssertTrue(coordinator.ui.isAIChatVisible)
    }

    @MainActor
    func testConsumeInitialChatQuestion_returnsValueThenNils() {
        let coordinator = TestableAppCoordinator()
        coordinator.ui.initialChatQuestion = "Tell me about this"

        let consumed = coordinator.consumeInitialChatQuestion()
        XCTAssertEqual(consumed, "Tell me about this")
        XCTAssertNil(coordinator.ui.initialChatQuestion)
    }

    @MainActor
    func testConsumeInitialChatQuestion_nilWhenNotSet() {
        let coordinator = TestableAppCoordinator()
        XCTAssertNil(coordinator.consumeInitialChatQuestion())
    }

    @MainActor
    func testToggleFavorite_flipsViaMetadataRepo() {
        let metadata = MockMetadataRepository()
        let coordinator = TestableAppCoordinator(metadata: metadata)
        let url = URL(fileURLWithPath: "/tmp/test.md")

        XCTAssertFalse(coordinator.isFavorite(url))
        coordinator.toggleFavorite(for: url)
        XCTAssertTrue(coordinator.isFavorite(url))
        coordinator.toggleFavorite(for: url)
        XCTAssertFalse(coordinator.isFavorite(url))
    }

    @MainActor
    func testSaveScrollPosition_storesPending() {
        let metadata = MockMetadataRepository()
        let coordinator = TestableAppCoordinator(metadata: metadata)
        let file = URL(fileURLWithPath: "/tmp/test.md")
        coordinator.navigation.selectFile(file)

        coordinator.saveScrollPosition(0.75)

        // Not flushed yet — pending position not written to repo
        XCTAssertNil(metadata.scrollPositions[file.path])
    }

    @MainActor
    func testFlushScrollPosition_writesPendingToRepo() {
        let metadata = MockMetadataRepository()
        let coordinator = TestableAppCoordinator(metadata: metadata)
        let file = URL(fileURLWithPath: "/tmp/test.md")
        coordinator.navigation.selectFile(file)

        coordinator.saveScrollPosition(0.75)
        coordinator.flushScrollPosition()

        XCTAssertEqual(metadata.scrollPositions[file.path], 0.75)
    }

    @MainActor
    func testFlushScrollPosition_noOpWhenNoPending() {
        let metadata = MockMetadataRepository()
        let coordinator = TestableAppCoordinator(metadata: metadata)

        // No crash, no write
        coordinator.flushScrollPosition()
        XCTAssertTrue(metadata.scrollPositions.isEmpty)
    }

    @MainActor
    func testCloseFolder_flushesScrollBeforeClearing() {
        let metadata = MockMetadataRepository()
        let coordinator = TestableAppCoordinator(metadata: metadata)
        let file = URL(fileURLWithPath: "/tmp/testfolder/file.md")

        coordinator.openFolder(URL(fileURLWithPath: "/tmp/testfolder"))
        coordinator.navigation.selectFile(file)
        coordinator.saveScrollPosition(0.9)

        coordinator.closeFolder()

        // Should have flushed before clearing
        XCTAssertEqual(metadata.scrollPositions[file.path], 0.9)
    }
}

// MARK: - FileLoadError Tests

final class FileLoadErrorTests: XCTestCase {

    func testFileTooLarge_formatsMBCorrectly() {
        let error = TestableFileLoadError.fileTooLarge(size: 5_242_880)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("5.0 MB"), "Expected '5.0 MB' in: \(description)")
    }

    func testFileTooLarge_formatsLargeSize() {
        let error = TestableFileLoadError.fileTooLarge(size: 15_728_640)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("15.0 MB"), "Expected '15.0 MB' in: \(description)")
    }

    func testFileTooLarge_mentionsMaxSize() {
        let error = TestableFileLoadError.fileTooLarge(size: 5_242_880)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("10 MB"))
    }

    func testInvalidEncoding_hasCorrectDescription() {
        let error = TestableFileLoadError.invalidEncoding
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("UTF-8"))
    }
}
