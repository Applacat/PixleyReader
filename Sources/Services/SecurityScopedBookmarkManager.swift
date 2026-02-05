import Foundation

// MARK: - Security Scoped Bookmark Manager

/// Manages security-scoped bookmarks for sandboxed macOS apps.
/// Consolidates bookmark handling logic previously duplicated across views.
@MainActor
final class SecurityScopedBookmarkManager {

    // MARK: - Shared Instance

    static let shared = SecurityScopedBookmarkManager()

    private init() {}

    // MARK: - Bookmark Key Generation

    /// Generates a consistent key for storing bookmarks by directory type.
    private func bookmarkKey(for directory: FileManager.SearchPathDirectory) -> String {
        "bookmark_\(directory.rawValue)"
    }

    // MARK: - Save Bookmark

    /// Saves a security-scoped bookmark for a URL.
    /// - Parameters:
    ///   - url: The URL to bookmark
    ///   - directory: The directory type (for consistent key naming)
    func saveBookmark(_ url: URL, for directory: FileManager.SearchPathDirectory) {
        let key = bookmarkKey(for: directory)

        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: key)
        } catch {
            // Silent failure - bookmark not saved but app continues
            print("Warning: Failed to save bookmark for \(directory): \(error)")
        }
    }

    // MARK: - Resolve Bookmark

    /// Resolves a previously saved bookmark to a URL.
    /// - Parameter directory: The directory type to resolve
    /// - Returns: The URL if bookmark exists and is valid, nil otherwise
    func resolveBookmark(for directory: FileManager.SearchPathDirectory) -> URL? {
        let key = bookmarkKey(for: directory)

        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
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
                // Bookmark is stale - try to refresh it
                return refreshStaleBookmark(url: url, for: directory)
            }

            return url
        } catch {
            // Bookmark resolution failed - remove stale data
            UserDefaults.standard.removeObject(forKey: key)
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
        // Try to access and re-create bookmark
        if url.startAccessingSecurityScopedResource() {
            saveBookmark(url, for: directory)
            return url
        }
        return nil
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

        // Try existing bookmark first
        if let resolvedURL = resolveBookmark(for: directory) {
            onAccessGranted(resolvedURL)
            return
        }

        // Try direct access (may trigger permission prompt)
        if directoryURL.startAccessingSecurityScopedResource() {
            // Permission granted - save for next time
            saveBookmark(directoryURL, for: directory)
            onAccessGranted(directoryURL)
        } else {
            // Need to request permission via panel
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

    /// Removes a saved bookmark.
    /// - Parameter directory: The directory type to clear
    func clearBookmark(for directory: FileManager.SearchPathDirectory) {
        let key = bookmarkKey(for: directory)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
