import XCTest
import SwiftData
import Foundation

// MARK: - Test-Only Model Definitions
// Since the main target is an executable (no @testable import),
// we mirror the SwiftData models and repository for testing.
// These must stay in sync with Sources/Persistence/*.swift.

@Model
private final class TestFileMetadata {
    @Attribute(.unique)
    var filePath: String
    var scrollPosition: Double
    var isFavorite: Bool
    var lastOpened: Date

    init(
        filePath: String,
        scrollPosition: Double = 0.0,
        isFavorite: Bool = false,
        lastOpened: Date = .now
    ) {
        self.filePath = filePath
        self.scrollPosition = scrollPosition
        self.isFavorite = isFavorite
        self.lastOpened = lastOpened
    }

    convenience init(url: URL) {
        self.init(filePath: url.path)
    }

    var url: URL {
        URL(fileURLWithPath: filePath)
    }
}

@Model
private final class TestBookmark {
    var id: UUID
    var filePath: String
    var lineNumber: Int
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        filePath: String,
        lineNumber: Int,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.note = note
        self.createdAt = createdAt
    }

    convenience init(url: URL, lineNumber: Int, note: String? = nil) {
        self.init(filePath: url.path, lineNumber: lineNumber, note: note)
    }

    var url: URL {
        URL(fileURLWithPath: filePath)
    }
}

// MARK: - Testable Repository

/// Test implementation mirroring SwiftDataMetadataRepository.
/// Uses the same patterns (FetchDescriptor, predicates, sort) as production code.
@MainActor
private final class TestableMetadataRepository {

    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Metadata

    func getMetadata(for url: URL) -> TestFileMetadata? {
        let path = url.path
        let descriptor = FetchDescriptor<TestFileMetadata>(
            predicate: #Predicate { $0.filePath == path }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func getOrCreateMetadata(for url: URL) -> TestFileMetadata {
        if let existing = getMetadata(for: url) {
            return existing
        }
        let metadata = TestFileMetadata(url: url)
        modelContext.insert(metadata)
        try? modelContext.save()
        return metadata
    }

    func saveScrollPosition(_ position: Double, for url: URL) {
        let metadata = getOrCreateMetadata(for: url)
        metadata.scrollPosition = position
        try? modelContext.save()
    }

    func updateLastOpened(for url: URL) {
        let metadata = getOrCreateMetadata(for: url)
        metadata.lastOpened = .now
        try? modelContext.save()
    }

    // MARK: - Favorites

    func setFavorite(_ isFavorite: Bool, for url: URL) {
        let metadata = getOrCreateMetadata(for: url)
        metadata.isFavorite = isFavorite
        try? modelContext.save()
    }

    func getFavorites() -> [URL] {
        let descriptor = FetchDescriptor<TestFileMetadata>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.lastOpened, order: .reverse)]
        )
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.map { $0.url }
    }

    func isFavorite(_ url: URL) -> Bool {
        getMetadata(for: url)?.isFavorite ?? false
    }

    // MARK: - Bookmarks

    func getBookmarks(for url: URL) -> [TestBookmark] {
        let path = url.path
        let descriptor = FetchDescriptor<TestBookmark>(
            predicate: #Predicate { $0.filePath == path },
            sortBy: [SortDescriptor(\.lineNumber)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addBookmark(for url: URL, lineNumber: Int, note: String? = nil) -> TestBookmark {
        let bookmark = TestBookmark(url: url, lineNumber: lineNumber, note: note)
        modelContext.insert(bookmark)
        try? modelContext.save()
        return bookmark
    }

    func deleteBookmark(_ id: UUID) {
        let descriptor = FetchDescriptor<TestBookmark>(
            predicate: #Predicate { $0.id == id }
        )
        if let results = try? modelContext.fetch(descriptor) {
            for bookmark in results {
                modelContext.delete(bookmark)
            }
            try? modelContext.save()
        }
    }

    func deleteAllBookmarks(for url: URL) {
        let bookmarks = getBookmarks(for: url)
        for bookmark in bookmarks {
            modelContext.delete(bookmark)
        }
        try? modelContext.save()
    }
}

// MARK: - Container Factory

/// Creates an in-memory ModelContainer for testing.
/// Mirrors MetadataContainerConfiguration.makeContainer(inMemory: true).
private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([TestFileMetadata.self, TestBookmark.self])
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [configuration])
}

// MARK: - Tests

final class FileMetadataRepositoryTests: XCTestCase {

    private var container: ModelContainer!
    private var repository: TestableMetadataRepository!

    override func setUp() async throws {
        let testContainer = try makeTestContainer()
        container = testContainer
        repository = await MainActor.run {
            TestableMetadataRepository(modelContext: testContainer.mainContext)
        }
    }

    override func tearDown() async throws {
        container = nil
        repository = nil
    }

    // MARK: - Metadata: getMetadata

    @MainActor
    func testGetMetadata_returnsNilForUnknownFile() {
        let url = URL(fileURLWithPath: "/test/unknown.md")

        let metadata = repository.getMetadata(for: url)

        XCTAssertNil(metadata)
    }

    // MARK: - Metadata: getOrCreateMetadata

    @MainActor
    func testGetOrCreateMetadata_createsIfMissing() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        let metadata = repository.getOrCreateMetadata(for: url)

        XCTAssertEqual(metadata.filePath, url.path)
        XCTAssertEqual(metadata.scrollPosition, 0.0)
        XCTAssertFalse(metadata.isFavorite)
    }

    @MainActor
    func testGetOrCreateMetadata_returnsExistingIfPresent() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        let first = repository.getOrCreateMetadata(for: url)
        first.scrollPosition = 0.75
        try? container.mainContext.save()

        let second = repository.getOrCreateMetadata(for: url)

        XCTAssertEqual(second.scrollPosition, 0.75, "Should return existing metadata, not create new")
    }

    @MainActor
    func testGetOrCreateMetadata_uniqueConstraintPreventsDuplicates() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        _ = repository.getOrCreateMetadata(for: url)
        _ = repository.getOrCreateMetadata(for: url)
        _ = repository.getOrCreateMetadata(for: url)

        // Fetch all metadata to verify only one exists
        let allDescriptor = FetchDescriptor<TestFileMetadata>()
        let allResults = try? container.mainContext.fetch(allDescriptor)
        XCTAssertEqual(allResults?.count, 1, "Unique constraint should prevent duplicates")
    }

    // MARK: - Metadata: saveScrollPosition

    @MainActor
    func testSaveScrollPosition_persistsValue() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        repository.saveScrollPosition(0.42, for: url)

        let metadata = repository.getMetadata(for: url)
        XCTAssertEqual(metadata?.scrollPosition, 0.42)
    }

    @MainActor
    func testSaveScrollPosition_updatesExistingValue() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        repository.saveScrollPosition(0.25, for: url)
        repository.saveScrollPosition(0.75, for: url)

        let metadata = repository.getMetadata(for: url)
        XCTAssertEqual(metadata?.scrollPosition, 0.75)
    }

    // MARK: - Metadata: updateLastOpened

    @MainActor
    func testUpdateLastOpened_setsRecentDate() {
        let url = URL(fileURLWithPath: "/test/doc.md")
        let beforeUpdate = Date.now

        repository.updateLastOpened(for: url)

        let metadata = repository.getMetadata(for: url)
        XCTAssertNotNil(metadata)
        XCTAssertGreaterThanOrEqual(metadata!.lastOpened, beforeUpdate)
    }

    // MARK: - Favorites: setFavorite / isFavorite

    @MainActor
    func testSetFavorite_marksAsFavorite() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        repository.setFavorite(true, for: url)

        XCTAssertTrue(repository.isFavorite(url))
    }

    @MainActor
    func testSetFavorite_unmarksFavorite() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        repository.setFavorite(true, for: url)
        repository.setFavorite(false, for: url)

        XCTAssertFalse(repository.isFavorite(url))
    }

    @MainActor
    func testIsFavorite_returnsFalseForUnknownFile() {
        let url = URL(fileURLWithPath: "/test/unknown.md")

        XCTAssertFalse(repository.isFavorite(url))
    }

    // MARK: - Favorites: getFavorites

    @MainActor
    func testGetFavorites_returnsOnlyFavorited() {
        let url1 = URL(fileURLWithPath: "/test/fav.md")
        let url2 = URL(fileURLWithPath: "/test/notfav.md")

        repository.setFavorite(true, for: url1)
        _ = repository.getOrCreateMetadata(for: url2) // exists but not favorited

        let favorites = repository.getFavorites()

        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.path, url1.path)
    }

    @MainActor
    func testGetFavorites_sortsByLastOpenedDescending() {
        let url1 = URL(fileURLWithPath: "/test/old.md")
        let url2 = URL(fileURLWithPath: "/test/new.md")

        // Create with explicit dates to avoid timing issues
        let oldMetadata = TestFileMetadata(
            filePath: url1.path,
            isFavorite: true,
            lastOpened: Date(timeIntervalSince1970: 1000)
        )
        let newMetadata = TestFileMetadata(
            filePath: url2.path,
            isFavorite: true,
            lastOpened: Date(timeIntervalSince1970: 2000)
        )

        container.mainContext.insert(oldMetadata)
        container.mainContext.insert(newMetadata)
        try? container.mainContext.save()

        let favorites = repository.getFavorites()

        XCTAssertEqual(favorites.count, 2)
        XCTAssertEqual(favorites[0].path, url2.path, "Newest should be first")
        XCTAssertEqual(favorites[1].path, url1.path, "Oldest should be last")
    }

    @MainActor
    func testGetFavorites_returnsEmptyWhenNone() {
        let favorites = repository.getFavorites()
        XCTAssertTrue(favorites.isEmpty)
    }

    // MARK: - Bookmarks: addBookmark

    @MainActor
    func testAddBookmark_createsWithCorrectData() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        let bookmark = repository.addBookmark(for: url, lineNumber: 42, note: "Important section")

        XCTAssertEqual(bookmark.filePath, url.path)
        XCTAssertEqual(bookmark.lineNumber, 42)
        XCTAssertEqual(bookmark.note, "Important section")
    }

    @MainActor
    func testAddBookmark_withoutNote() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        let bookmark = repository.addBookmark(for: url, lineNumber: 10)

        XCTAssertNil(bookmark.note)
        XCTAssertEqual(bookmark.lineNumber, 10)
    }

    // MARK: - Bookmarks: getBookmarks

    @MainActor
    func testGetBookmarks_sortedByLineNumber() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        repository.addBookmark(for: url, lineNumber: 50)
        repository.addBookmark(for: url, lineNumber: 10)
        repository.addBookmark(for: url, lineNumber: 30)

        let bookmarks = repository.getBookmarks(for: url)

        XCTAssertEqual(bookmarks.count, 3)
        XCTAssertEqual(bookmarks[0].lineNumber, 10)
        XCTAssertEqual(bookmarks[1].lineNumber, 30)
        XCTAssertEqual(bookmarks[2].lineNumber, 50)
    }

    @MainActor
    func testGetBookmarks_returnsEmptyForUnknownFile() {
        let url = URL(fileURLWithPath: "/test/unknown.md")

        let bookmarks = repository.getBookmarks(for: url)

        XCTAssertTrue(bookmarks.isEmpty)
    }

    @MainActor
    func testGetBookmarks_isolatedPerFile() {
        let url1 = URL(fileURLWithPath: "/test/doc1.md")
        let url2 = URL(fileURLWithPath: "/test/doc2.md")

        repository.addBookmark(for: url1, lineNumber: 10)
        repository.addBookmark(for: url1, lineNumber: 20)
        repository.addBookmark(for: url2, lineNumber: 5)

        XCTAssertEqual(repository.getBookmarks(for: url1).count, 2)
        XCTAssertEqual(repository.getBookmarks(for: url2).count, 1)
    }

    // MARK: - Bookmarks: deleteBookmark

    @MainActor
    func testDeleteBookmark_removesFromPersistence() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        let bookmark = repository.addBookmark(for: url, lineNumber: 42)
        repository.deleteBookmark(bookmark.id)

        let bookmarks = repository.getBookmarks(for: url)
        XCTAssertTrue(bookmarks.isEmpty)
    }

    @MainActor
    func testDeleteBookmark_noopForUnknownId() {
        let url = URL(fileURLWithPath: "/test/doc.md")
        repository.addBookmark(for: url, lineNumber: 10)

        // Delete with unknown ID - should not crash or affect existing
        repository.deleteBookmark(UUID())

        XCTAssertEqual(repository.getBookmarks(for: url).count, 1)
    }

    // MARK: - Bookmarks: deleteAllBookmarks

    @MainActor
    func testDeleteAllBookmarks_clearsFileBookmarks() {
        let url1 = URL(fileURLWithPath: "/test/doc1.md")
        let url2 = URL(fileURLWithPath: "/test/doc2.md")

        repository.addBookmark(for: url1, lineNumber: 10)
        repository.addBookmark(for: url1, lineNumber: 20)
        repository.addBookmark(for: url2, lineNumber: 5)

        repository.deleteAllBookmarks(for: url1)

        XCTAssertTrue(repository.getBookmarks(for: url1).isEmpty, "All url1 bookmarks deleted")
        XCTAssertEqual(repository.getBookmarks(for: url2).count, 1, "url2 bookmarks untouched")
    }

    @MainActor
    func testDeleteAllBookmarks_noopForFileWithNoBookmarks() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        // Should not crash
        repository.deleteAllBookmarks(for: url)

        XCTAssertTrue(repository.getBookmarks(for: url).isEmpty)
    }

    // MARK: - Cross-Feature: Metadata + Bookmarks Independence

    @MainActor
    func testMetadataAndBookmarks_independent() {
        let url = URL(fileURLWithPath: "/test/doc.md")

        // Set up metadata
        repository.setFavorite(true, for: url)
        repository.saveScrollPosition(0.5, for: url)

        // Add bookmarks
        repository.addBookmark(for: url, lineNumber: 10)
        repository.addBookmark(for: url, lineNumber: 20)

        // Verify both exist independently
        XCTAssertTrue(repository.isFavorite(url))
        XCTAssertEqual(repository.getMetadata(for: url)?.scrollPosition, 0.5)
        XCTAssertEqual(repository.getBookmarks(for: url).count, 2)

        // Delete bookmarks - metadata should survive
        repository.deleteAllBookmarks(for: url)
        XCTAssertTrue(repository.isFavorite(url), "Metadata survives bookmark deletion")
        XCTAssertEqual(repository.getMetadata(for: url)?.scrollPosition, 0.5)
    }
}
