import Foundation

// MARK: - File Metadata Repository Protocol

/// Repository for persisting file reading state.
///
/// Abstracts the persistence mechanism (SwiftData) behind a protocol
/// for testability and potential future backends.
@MainActor
public protocol FileMetadataRepository {

    // MARK: - Metadata Operations

    /// Retrieves metadata for a file, or nil if none exists
    func getMetadata(for url: URL) -> FileMetadata?

    /// Gets or creates metadata for a file
    func getOrCreateMetadata(for url: URL) -> FileMetadata

    /// Saves the scroll position for a file
    func saveScrollPosition(_ position: Double, for url: URL)

    /// Updates the last opened date for a file
    func updateLastOpened(for url: URL)

    // MARK: - Favorites Operations

    /// Sets the favorite status for a file
    func setFavorite(_ isFavorite: Bool, for url: URL)

    /// Returns all favorited file URLs
    func getFavorites() -> [URL]

    /// Checks if a file is favorited
    func isFavorite(_ url: URL) -> Bool

    // MARK: - Bookmark Operations

    /// Returns all bookmarks for a file, sorted by line number
    func getBookmarks(for url: URL) -> [Bookmark]

    /// Adds a bookmark at the specified line
    @discardableResult
    func addBookmark(for url: URL, lineNumber: Int, note: String?) -> Bookmark

    /// Deletes a bookmark by ID
    func deleteBookmark(_ id: UUID)

    /// Deletes all bookmarks for a file
    func deleteAllBookmarks(for url: URL)
}

// MARK: - Default Implementations

public extension FileMetadataRepository {

    /// Convenience: Add bookmark without note
    @discardableResult
    func addBookmark(for url: URL, lineNumber: Int) -> Bookmark {
        addBookmark(for: url, lineNumber: lineNumber, note: nil)
    }
}
