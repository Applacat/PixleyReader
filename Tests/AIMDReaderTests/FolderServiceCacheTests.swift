import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// Since FolderService is in the main app (executable target),
// we mirror the cache invalidation logic here for testing.

/// Test version of the cache invalidation logic
@MainActor
private final class TestableCacheManager {

    var cache: [String: String] = [:]  // path -> cached data
    var invalidationLog: [String] = []  // tracks which paths were invalidated

    func addCacheEntry(path: String, data: String = "cached") {
        cache[path] = data
    }

    /// NEW behavior: invalidate folder and all ancestors
    func invalidateCache(for url: URL) {
        var currentURL = url
        var invalidatedCount = 0

        // Invalidate the target folder
        if cache.removeValue(forKey: currentURL.path) != nil {
            invalidationLog.append(currentURL.path)
            invalidatedCount += 1
        }

        // Invalidate all ancestor folders
        while true {
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path || parent.path == "/" {
                break
            }
            if cache.removeValue(forKey: parent.path) != nil {
                invalidationLog.append(parent.path)
                invalidatedCount += 1
            }
            currentURL = parent
        }
    }

    /// OLD behavior: only invalidate exact path
    func invalidateCacheOldBehavior(for url: URL) {
        cache.removeValue(forKey: url.path)
    }

    func clearInvalidationLog() {
        invalidationLog.removeAll()
    }
}

// MARK: - Tests

final class FolderServiceCacheTests: XCTestCase {

    private var manager: TestableCacheManager!

    @MainActor
    override func setUp() {
        super.setUp()
        manager = TestableCacheManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Basic Invalidation Tests

    @MainActor
    func testInvalidateCache_removesTargetFolder() {
        // Given: Cached folder
        let folderPath = "/Users/test/Documents/Project"
        manager.addCacheEntry(path: folderPath)
        XCTAssertNotNil(manager.cache[folderPath])

        // When: Invalidate
        let url = URL(fileURLWithPath: folderPath)
        manager.invalidateCache(for: url)

        // Then: Entry removed
        XCTAssertNil(manager.cache[folderPath])
    }

    @MainActor
    func testInvalidateCache_removesAncestorFolders() {
        // Given: Folder hierarchy in cache
        let root = "/Users/test"
        let parent = "/Users/test/Documents"
        let target = "/Users/test/Documents/Project"
        let child = "/Users/test/Documents/Project/Subfolder"

        manager.addCacheEntry(path: root)
        manager.addCacheEntry(path: parent)
        manager.addCacheEntry(path: target)
        manager.addCacheEntry(path: child)

        // When: Invalidate target folder
        manager.invalidateCache(for: URL(fileURLWithPath: target))

        // Then: Target AND ancestors removed
        XCTAssertNil(manager.cache[target], "Target should be invalidated")
        XCTAssertNil(manager.cache[parent], "Parent should be invalidated")
        XCTAssertNil(manager.cache[root], "Grandparent should be invalidated")

        // But child is NOT affected (we didn't go down, only up)
        XCTAssertNotNil(manager.cache[child], "Child should NOT be invalidated")
    }

    @MainActor
    func testInvalidateCache_logsInvalidatedPaths() {
        // Given: Folder hierarchy
        let parent = "/Users/test/Documents"
        let target = "/Users/test/Documents/Project"

        manager.addCacheEntry(path: parent)
        manager.addCacheEntry(path: target)

        // When: Invalidate
        manager.invalidateCache(for: URL(fileURLWithPath: target))

        // Then: Log shows both invalidations
        XCTAssertTrue(manager.invalidationLog.contains(target))
        XCTAssertTrue(manager.invalidationLog.contains(parent))
    }

    // MARK: - Ancestor Invalidation Tests

    @MainActor
    func testInvalidateCache_deepNesting_invalidatesAllAncestors() throws {
        // Given: Deep folder hierarchy
        let paths = [
            "/Users/test",
            "/Users/test/Documents",
            "/Users/test/Documents/Work",
            "/Users/test/Documents/Work/2024",
            "/Users/test/Documents/Work/2024/Q1",
            "/Users/test/Documents/Work/2024/Q1/Reports"
        ]

        for path in paths {
            manager.addCacheEntry(path: path)
        }

        // When: Invalidate deepest folder
        let deepestPath = try XCTUnwrap(paths.last)
        let deepest = URL(fileURLWithPath: deepestPath)
        manager.invalidateCache(for: deepest)

        // Then: ALL ancestors invalidated
        for path in paths {
            XCTAssertNil(manager.cache[path], "Path \(path) should be invalidated")
        }
    }

    @MainActor
    func testInvalidateCache_stopsAtRoot() {
        // Given: Path that goes to root
        let path = "/tmp/test"
        manager.addCacheEntry(path: path)
        manager.addCacheEntry(path: "/tmp")
        manager.addCacheEntry(path: "/")  // Root should be skipped

        // When: Invalidate
        manager.invalidateCache(for: URL(fileURLWithPath: path))

        // Then: Doesn't crash, stops before root
        XCTAssertNil(manager.cache[path])
        XCTAssertNil(manager.cache["/tmp"])
        // Root may or may not be in log depending on implementation
    }

    // MARK: - Markdown Count Staleness Scenario

    @MainActor
    func testScenario_addFileInSubfolder_invalidatesParentCount() {
        // Scenario: User adds a new .md file in /Documents/Project/Notes
        // The markdown count for /Documents and /Documents/Project becomes stale

        // Given: Cached folder tree
        let documents = "/Users/test/Documents"
        let project = "/Users/test/Documents/Project"
        let notes = "/Users/test/Documents/Project/Notes"

        manager.addCacheEntry(path: documents, data: "markdownCount: 5")
        manager.addCacheEntry(path: project, data: "markdownCount: 3")
        manager.addCacheEntry(path: notes, data: "markdownCount: 2")

        // When: File added in notes folder -> invalidate notes
        manager.invalidateCache(for: URL(fileURLWithPath: notes))

        // Then: ALL parent caches invalidated (they have stale counts)
        XCTAssertNil(manager.cache[notes], "Notes cache should be invalid")
        XCTAssertNil(manager.cache[project], "Project cache should be invalid (stale count)")
        XCTAssertNil(manager.cache[documents], "Documents cache should be invalid (stale count)")
    }

    // MARK: - OLD Behavior Comparison

    @MainActor
    func testOldBehavior_doesNotInvalidateAncestors() {
        // Demonstrates the bug that was fixed

        // Given: Folder hierarchy
        let parent = "/Users/test/Documents"
        let target = "/Users/test/Documents/Project"

        manager.addCacheEntry(path: parent, data: "stale_count")
        manager.addCacheEntry(path: target)

        // When: OLD invalidation (only target)
        manager.invalidateCacheOldBehavior(for: URL(fileURLWithPath: target))

        // Then: Parent NOT invalidated (BUG - has stale markdown count)
        XCTAssertNil(manager.cache[target], "Target should be removed")
        XCTAssertNotNil(manager.cache[parent], "OLD behavior: Parent stays (with stale count!)")
    }

    // MARK: - Edge Cases

    @MainActor
    func testInvalidateCache_nonexistentPath_noOp() {
        // Given: Cache with some entries
        manager.addCacheEntry(path: "/existing")

        // When: Invalidate non-cached path
        manager.invalidateCache(for: URL(fileURLWithPath: "/nonexistent/path"))

        // Then: No crash, existing cache unaffected
        XCTAssertNotNil(manager.cache["/existing"])
    }

    @MainActor
    func testInvalidateCache_emptyCache_noOp() {
        // Given: Empty cache

        // When: Invalidate
        manager.invalidateCache(for: URL(fileURLWithPath: "/any/path"))

        // Then: No crash
        XCTAssertTrue(manager.cache.isEmpty)
    }

    @MainActor
    func testInvalidateCache_partialAncestorsInCache() {
        // Given: Only some ancestors cached
        let grandparent = "/Users/test/Documents"
        // parent NOT in cache
        let target = "/Users/test/Documents/Project/Subfolder"

        manager.addCacheEntry(path: grandparent)
        manager.addCacheEntry(path: target)

        // When: Invalidate target
        manager.invalidateCache(for: URL(fileURLWithPath: target))

        // Then: Both target and grandparent invalidated (even though parent wasn't cached)
        XCTAssertNil(manager.cache[target])
        XCTAssertNil(manager.cache[grandparent])
    }

    @MainActor
    func testInvalidateCache_siblingFoldersUnaffected() {
        // Given: Sibling folders
        let parent = "/Users/test/Documents"
        let target = "/Users/test/Documents/ProjectA"
        let sibling = "/Users/test/Documents/ProjectB"

        manager.addCacheEntry(path: parent)
        manager.addCacheEntry(path: target)
        manager.addCacheEntry(path: sibling)

        // When: Invalidate target
        manager.invalidateCache(for: URL(fileURLWithPath: target))

        // Then: Sibling unaffected
        XCTAssertNil(manager.cache[target])
        XCTAssertNil(manager.cache[parent])  // Parent invalidated
        XCTAssertNotNil(manager.cache[sibling], "Sibling should NOT be affected")
    }
}
