import Foundation
import os.log

private let log = Logger(subsystem: "com.aimd.reader", category: "BookmarkManager")

// MARK: - Security Scoped Bookmark Manager

/// Manages security-scoped bookmarks for sandboxed macOS apps.
/// Bookmark data stored as files in Application Support/AIMDReader/Bookmarks/.
/// Migrates legacy UserDefaults bookmarks on first access.
@MainActor
final class SecurityScopedBookmarkManager {

    // MARK: - Shared Instance

    static let shared = SecurityScopedBookmarkManager()

    private init() {}

    // MARK: - Storage Paths

    /// Directory for bookmark file storage
    private var bookmarksDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
            .appendingPathComponent("Bookmarks")
    }

    /// File path for a bookmark by directory type
    private func bookmarkFileURL(for directory: FileManager.SearchPathDirectory) -> URL? {
        bookmarksDirectory?.appendingPathComponent("bookmark_\(directory.rawValue).bookmark")
    }

    /// Legacy key for UserDefaults migration
    private func legacyBookmarkKey(for directory: FileManager.SearchPathDirectory) -> String {
        "bookmark_\(directory.rawValue)"
    }

    // MARK: - Save Bookmark

    /// Saves a security-scoped bookmark for a URL.
    /// - Parameters:
    ///   - url: The URL to bookmark
    ///   - directory: The directory type (for consistent key naming)
    func saveBookmark(_ url: URL, for directory: FileManager.SearchPathDirectory) {
        guard let fileURL = bookmarkFileURL(for: directory) else { return }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try bookmarkData.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            log.error("Failed to save bookmark for directory \(directory.rawValue): \(error.localizedDescription)")
        }
    }

    // MARK: - Resolve Bookmark

    /// Resolves a previously saved bookmark to a URL.
    /// Checks file storage first, then migrates from UserDefaults if needed.
    /// - Parameter directory: The directory type to resolve
    /// - Returns: The URL if bookmark exists and is valid, nil otherwise
    func resolveBookmark(for directory: FileManager.SearchPathDirectory) -> URL? {
        let bookmarkData: Data

        if let fileURL = bookmarkFileURL(for: directory),
           let data = try? Data(contentsOf: fileURL) {
            bookmarkData = data
        } else if let legacyData = migrateLegacyBookmark(for: directory) {
            bookmarkData = legacyData
        } else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                return refreshStaleBookmark(url: url, for: directory)
            }

            return url
        } catch {
            if let fileURL = bookmarkFileURL(for: directory) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            log.warning("Bookmark resolution failed for directory \(directory.rawValue): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Refresh Stale Bookmark

    /// Attempts to refresh a stale bookmark.
    /// - Parameters:
    ///   - url: The URL from the stale bookmark
    ///   - directory: The directory type
    /// - Returns: The refreshed URL if successful, nil otherwise
    private func refreshStaleBookmark(url: URL, for directory: FileManager.SearchPathDirectory) -> URL? {
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            saveBookmark(url, for: directory)
            return url
        }
        return nil
    }

    // MARK: - Legacy Migration

    /// Migrates a legacy UserDefaults bookmark to file storage.
    /// Returns the bookmark data if found, nil otherwise.
    private func migrateLegacyBookmark(for directory: FileManager.SearchPathDirectory) -> Data? {
        let key = legacyBookmarkKey(for: directory)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        if let fileURL = bookmarkFileURL(for: directory) {
            let dir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            do {
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                UserDefaults.standard.removeObject(forKey: key)
                log.info("Migrated bookmark for directory \(directory.rawValue) from UserDefaults to file storage")
            } catch {
                log.error("Failed to migrate bookmark for directory \(directory.rawValue): \(error.localizedDescription)")
            }
        }

        return data
    }

    // MARK: - Get or Request Access

    /// Attempts to get access to a standard directory.
    /// First tries existing bookmark, then requests permission if needed.
    /// - Parameters:
    ///   - directory: The standard directory type
    ///   - onAccessGranted: Callback when access is granted with the URL
    ///   - onPermissionNeeded: Callback when user needs to grant permission via panel
    func getOrRequestAccess(
        to directory: FileManager.SearchPathDirectory,
        onAccessGranted: @escaping (URL) -> Void,
        onPermissionNeeded: @escaping (URL) -> Void
    ) {
        guard let directoryURL = FileManager.default.urls(for: directory, in: .userDomainMask).first else {
            return
        }

        if let resolvedURL = resolveBookmark(for: directory) {
            onAccessGranted(resolvedURL)
            return
        }

        if directoryURL.startAccessingSecurityScopedResource() {
            saveBookmark(directoryURL, for: directory)
            onAccessGranted(directoryURL)
        } else {
            onPermissionNeeded(directoryURL)
        }
    }

    // MARK: - Access Check

    /// Checks if we have access to a directory without modifying state.
    /// - Parameter directory: The directory type to check
    /// - Returns: True if we have a valid bookmark for this directory
    func hasAccess(to directory: FileManager.SearchPathDirectory) -> Bool {
        resolveBookmark(for: directory) != nil
    }

    // MARK: - Clear Bookmark

    /// Removes a saved bookmark from file storage and legacy UserDefaults.
    /// - Parameter directory: The directory type to clear
    func clearBookmark(for directory: FileManager.SearchPathDirectory) {
        if let fileURL = bookmarkFileURL(for: directory) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let key = legacyBookmarkKey(for: directory)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
