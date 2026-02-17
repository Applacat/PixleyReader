import XCTest
import Foundation

// MARK: - Test Helpers

extension String {
    /// Safely convert string to Data for tests - returns empty Data if conversion fails
    var testData: Data {
        data(using: .utf8) ?? Data()
    }
}

// MARK: - Test-Only Type Definitions
// Since RecentFoldersManager is in the main app (executable target),
// we mirror the implementation here for testing the logic.

/// Test version of RecentFolder
private struct TestableRecentFolder: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let bookmarkData: Data
    let dateOpened: Date

    init(url: URL, bookmarkData: Data) {
        self.id = UUID()
        self.name = url.lastPathComponent
        self.path = url.path
        self.bookmarkData = bookmarkData
        self.dateOpened = Date()
    }

    init(id: UUID, name: String, path: String, bookmarkData: Data, dateOpened: Date) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.dateOpened = dateOpened
    }
}

/// Test version of RecentFoldersManager
@MainActor
private final class TestableRecentFoldersManager {

    private var folders: [TestableRecentFolder] = []
    let maxRecents = 10

    func getRecentFolders() -> [TestableRecentFolder] {
        folders.sorted { $0.dateOpened > $1.dateOpened }
    }

    func addFolder(_ url: URL, bookmarkData: Data) {
        let newFolder = TestableRecentFolder(url: url, bookmarkData: bookmarkData)

        // Remove existing entry for same path
        folders.removeAll { $0.path == url.path }

        // Add new entry at the beginning
        folders.insert(newFolder, at: 0)

        // Trim to max
        if folders.count > maxRecents {
            folders = Array(folders.prefix(maxRecents))
        }
    }

    /// OLD behavior: calling addFolder for stale refresh (WRONG - creates duplicate/reorders)
    func refreshStaleBookmarkOldWay(_ folder: TestableRecentFolder, url: URL, newBookmarkData: Data) {
        addFolder(url, bookmarkData: newBookmarkData)
    }

    /// NEW behavior: refresh in-place without changing order
    func refreshStaleBookmark(_ folder: TestableRecentFolder, url: URL, newBookmarkData: Data) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        // Create updated folder with same ID and dateOpened (preserves order)
        let updatedFolder = TestableRecentFolder(
            id: folder.id,
            name: folder.name,
            path: folder.path,
            bookmarkData: newBookmarkData,
            dateOpened: folder.dateOpened
        )

        folders[index] = updatedFolder
    }

    func clearAll() {
        folders.removeAll()
    }
}

// MARK: - Tests

final class RecentFoldersManagerTests: XCTestCase {

    private var manager: TestableRecentFoldersManager!

    @MainActor
    override func setUp() {
        super.setUp()
        manager = TestableRecentFoldersManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Basic Tests

    @MainActor
    func testAddFolder_addsToList() {
        // Given: Empty list
        XCTAssertTrue(manager.getRecentFolders().isEmpty)

        // When: Add folder
        let url = URL(fileURLWithPath: "/Users/test/Documents")
        manager.addFolder(url, bookmarkData: "bookmark".testData)

        // Then: Folder is in list
        XCTAssertEqual(manager.getRecentFolders().count, 1)
        XCTAssertEqual(manager.getRecentFolders().first?.path, url.path)
    }

    @MainActor
    func testAddFolder_removesDuplicatePath() {
        // Given: Folder already in list
        let url = URL(fileURLWithPath: "/Users/test/Documents")
        manager.addFolder(url, bookmarkData: "old_bookmark".testData)

        // When: Add same path again
        manager.addFolder(url, bookmarkData: "new_bookmark".testData)

        // Then: Only one entry (no duplicates)
        XCTAssertEqual(manager.getRecentFolders().count, 1)
    }

    // MARK: - Stale Bookmark Refresh Tests (NEW BEHAVIOR)

    @MainActor
    func testRefreshStaleBookmark_updatesBookmarkInPlace() throws {
        // Given: Folder in list with old bookmark
        let url = URL(fileURLWithPath: "/Users/test/Documents")
        let oldBookmark = "old_bookmark".testData
        manager.addFolder(url, bookmarkData: oldBookmark)

        let folder = try XCTUnwrap(manager.getRecentFolders().first)
        let originalId = folder.id
        let originalDate = folder.dateOpened

        // When: Refresh stale bookmark
        let newBookmark = "new_bookmark".testData
        manager.refreshStaleBookmark(folder, url: url, newBookmarkData: newBookmark)

        // Then: Bookmark updated, ID and date preserved
        let refreshed = try XCTUnwrap(manager.getRecentFolders().first)
        XCTAssertEqual(refreshed.id, originalId)
        XCTAssertEqual(refreshed.dateOpened, originalDate)
        XCTAssertEqual(refreshed.bookmarkData, newBookmark)
    }

    @MainActor
    func testRefreshStaleBookmark_preservesOrder() throws {
        // Given: Multiple folders
        let url1 = URL(fileURLWithPath: "/Users/test/Folder1")
        let url2 = URL(fileURLWithPath: "/Users/test/Folder2")
        let url3 = URL(fileURLWithPath: "/Users/test/Folder3")

        manager.addFolder(url1, bookmarkData: "b1".testData)
        // Small delay to ensure different timestamps
        Thread.sleep(forTimeInterval: 0.01)
        manager.addFolder(url2, bookmarkData: "b2".testData)
        Thread.sleep(forTimeInterval: 0.01)
        manager.addFolder(url3, bookmarkData: "b3".testData)

        // url3 is most recent, url1 is oldest
        let folders = manager.getRecentFolders()
        XCTAssertEqual(folders.map { $0.name }, ["Folder3", "Folder2", "Folder1"])

        // When: Refresh stale bookmark on url1 (oldest)
        let folder1 = try XCTUnwrap(folders.last)  // url1 is last (oldest)
        manager.refreshStaleBookmark(folder1, url: url1, newBookmarkData: "new_b1".testData)

        // Then: Order is PRESERVED (url1 still oldest)
        let afterRefresh = manager.getRecentFolders()
        XCTAssertEqual(afterRefresh.map { $0.name }, ["Folder3", "Folder2", "Folder1"])
    }

    @MainActor
    func testRefreshStaleBookmark_doesNotCreateDuplicate() throws {
        // Given: Single folder
        let url = URL(fileURLWithPath: "/Users/test/Documents")
        manager.addFolder(url, bookmarkData: "old".testData)
        XCTAssertEqual(manager.getRecentFolders().count, 1)

        let folder = try XCTUnwrap(manager.getRecentFolders().first)

        // When: Refresh
        manager.refreshStaleBookmark(folder, url: url, newBookmarkData: "new".testData)

        // Then: Still only one entry
        XCTAssertEqual(manager.getRecentFolders().count, 1)
    }

    // MARK: - OLD Behavior Tests (for comparison)

    @MainActor
    func testOldRefreshBehavior_changesOrder() throws {
        // This test demonstrates the OLD (incorrect) behavior

        // Given: Multiple folders
        let url1 = URL(fileURLWithPath: "/Users/test/Folder1")
        let url2 = URL(fileURLWithPath: "/Users/test/Folder2")
        let url3 = URL(fileURLWithPath: "/Users/test/Folder3")

        manager.addFolder(url1, bookmarkData: "b1".testData)
        Thread.sleep(forTimeInterval: 0.01)
        manager.addFolder(url2, bookmarkData: "b2".testData)
        Thread.sleep(forTimeInterval: 0.01)
        manager.addFolder(url3, bookmarkData: "b3".testData)

        // url3 is most recent, url1 is oldest
        let folders = manager.getRecentFolders()
        XCTAssertEqual(folders.map { $0.name }, ["Folder3", "Folder2", "Folder1"])

        // When: OLD way - refresh by calling addFolder (WRONG)
        let folder1 = try XCTUnwrap(folders.last)  // url1 is last
        manager.refreshStaleBookmarkOldWay(folder1, url: url1, newBookmarkData: "new_b1".testData)

        // Then: Order CHANGED (url1 moved to front - this is the bug!)
        let afterRefresh = manager.getRecentFolders()
        // OLD behavior: url1 is now most recent because addFolder inserts at front
        XCTAssertEqual(afterRefresh.first?.name, "Folder1")
    }

    // MARK: - Edge Cases

    @MainActor
    func testRefreshStaleBookmark_nonexistentFolder_noOp() {
        // Given: Folder not in list
        let ghostFolder = TestableRecentFolder(
            url: URL(fileURLWithPath: "/nonexistent"),
            bookmarkData: "ghost".testData
        )

        // When: Try to refresh
        manager.refreshStaleBookmark(ghostFolder, url: URL(fileURLWithPath: "/nonexistent"), newBookmarkData: "new".testData)

        // Then: No crash, no changes
        XCTAssertTrue(manager.getRecentFolders().isEmpty)
    }

    @MainActor
    func testRefreshStaleBookmark_preservesName() throws {
        // Given: Folder with specific name
        let url = URL(fileURLWithPath: "/Users/test/MyDocuments")
        manager.addFolder(url, bookmarkData: "old".testData)

        let folder = try XCTUnwrap(manager.getRecentFolders().first)
        XCTAssertEqual(folder.name, "MyDocuments")

        // When: Refresh
        manager.refreshStaleBookmark(folder, url: url, newBookmarkData: "new".testData)

        // Then: Name preserved
        XCTAssertEqual(manager.getRecentFolders().first?.name, "MyDocuments")
    }
}
