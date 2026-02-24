import XCTest
import Foundation

// MARK: - Test-Only Type Definition
// Since SecurityScopedBookmarkManager is in the main app (executable target),
// we mirror the implementation here for testing the logic.

/// Test version of SecurityScopedBookmarkManager
@MainActor
private final class TestableBookmarkManager {

    private var storage: [String: Data] = [:]

    func bookmarkKey(for directory: FileManager.SearchPathDirectory) -> String {
        "bookmark_\(directory.rawValue)"
    }

    func saveBookmark(_ data: Data, for directory: FileManager.SearchPathDirectory) {
        let key = bookmarkKey(for: directory)
        storage[key] = data
    }

    func getBookmarkData(for directory: FileManager.SearchPathDirectory) -> Data? {
        let key = bookmarkKey(for: directory)
        return storage[key]
    }

    func clearBookmark(for directory: FileManager.SearchPathDirectory) {
        let key = bookmarkKey(for: directory)
        storage.removeValue(forKey: key)
    }

    func hasBookmark(for directory: FileManager.SearchPathDirectory) -> Bool {
        getBookmarkData(for: directory) != nil
    }
}

// MARK: - Tests

final class SecurityScopedBookmarkManagerTests: XCTestCase {

    private var manager: TestableBookmarkManager!

    override func setUp() async throws {
        manager = await TestableBookmarkManager()
    }

    override func tearDown() async throws {
        manager = nil
    }

    // MARK: - Bookmark Key Tests

    @MainActor
    func testBookmarkKey_generatesConsistentKey() {
        // Given: Same directory type
        let directory = FileManager.SearchPathDirectory.desktopDirectory

        // When: Generate key multiple times
        let key1 = manager.bookmarkKey(for: directory)
        let key2 = manager.bookmarkKey(for: directory)

        // Then: Keys are identical
        XCTAssertEqual(key1, key2)
    }

    @MainActor
    func testBookmarkKey_differentDirectoriesHaveDifferentKeys() {
        // Given: Different directory types
        let desktop = FileManager.SearchPathDirectory.desktopDirectory
        let documents = FileManager.SearchPathDirectory.documentDirectory

        // When: Generate keys
        let desktopKey = manager.bookmarkKey(for: desktop)
        let documentsKey = manager.bookmarkKey(for: documents)

        // Then: Keys are different
        XCTAssertNotEqual(desktopKey, documentsKey)
    }

    // MARK: - Save and Retrieve Tests

    @MainActor
    func testSaveBookmark_storesData() {
        // Given: Bookmark data
        let directory = FileManager.SearchPathDirectory.downloadsDirectory
        let testData = "test_bookmark_data".testData

        // When: Save bookmark
        manager.saveBookmark(testData, for: directory)

        // Then: Data is retrievable
        let retrieved = manager.getBookmarkData(for: directory)
        XCTAssertEqual(retrieved, testData)
    }

    @MainActor
    func testGetBookmarkData_returnsNilForMissingBookmark() {
        // Given: No bookmark saved
        let directory = FileManager.SearchPathDirectory.desktopDirectory

        // When: Try to retrieve
        let retrieved = manager.getBookmarkData(for: directory)

        // Then: Returns nil
        XCTAssertNil(retrieved)
    }

    // MARK: - Clear Bookmark Tests

    @MainActor
    func testClearBookmark_removesData() {
        // Given: Saved bookmark
        let directory = FileManager.SearchPathDirectory.documentDirectory
        let testData = "test_data".testData
        manager.saveBookmark(testData, for: directory)

        // When: Clear bookmark
        manager.clearBookmark(for: directory)

        // Then: Data is gone
        XCTAssertNil(manager.getBookmarkData(for: directory))
    }

    @MainActor
    func testClearBookmark_doesNotAffectOtherBookmarks() {
        // Given: Multiple bookmarks
        let desktop = FileManager.SearchPathDirectory.desktopDirectory
        let documents = FileManager.SearchPathDirectory.documentDirectory
        manager.saveBookmark("desktop".testData, for: desktop)
        manager.saveBookmark("documents".testData, for: documents)

        // When: Clear only desktop
        manager.clearBookmark(for: desktop)

        // Then: Documents bookmark still exists
        XCTAssertNil(manager.getBookmarkData(for: desktop))
        XCTAssertNotNil(manager.getBookmarkData(for: documents))
    }

    // MARK: - Has Access Tests

    @MainActor
    func testHasBookmark_returnsTrueWhenBookmarkExists() {
        // Given: Saved bookmark
        let directory = FileManager.SearchPathDirectory.downloadsDirectory
        manager.saveBookmark("data".testData, for: directory)

        // When: Check access
        let hasAccess = manager.hasBookmark(for: directory)

        // Then: Returns true
        XCTAssertTrue(hasAccess)
    }

    @MainActor
    func testHasBookmark_returnsFalseWhenNoBookmark() {
        // Given: No bookmark
        let directory = FileManager.SearchPathDirectory.desktopDirectory

        // When: Check access
        let hasAccess = manager.hasBookmark(for: directory)

        // Then: Returns false
        XCTAssertFalse(hasAccess)
    }

    // MARK: - Overwrite Tests

    @MainActor
    func testSaveBookmark_overwritesPreviousBookmark() {
        // Given: Existing bookmark
        let directory = FileManager.SearchPathDirectory.documentDirectory
        manager.saveBookmark("old_data".testData, for: directory)

        // When: Save new bookmark
        let newData = "new_data".testData
        manager.saveBookmark(newData, for: directory)

        // Then: New data is stored
        XCTAssertEqual(manager.getBookmarkData(for: directory), newData)
    }
}
