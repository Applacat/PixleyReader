import Foundation

// MARK: - Recent Folder

/// A recently opened folder with its security-scoped bookmark
struct RecentFolder: Identifiable, Codable {
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
}

// MARK: - Recent Folders Manager

/// Manages recently opened folders with security-scoped bookmarks.
/// Bookmarks allow the app to regain access to folders across launches.
@MainActor
final class RecentFoldersManager {

    static let shared = RecentFoldersManager()

    private let maxRecents = 10
    private let userDefaultsKey = "recentFolders"

    private init() {}

    // MARK: - Public API

    /// Get list of recent folders, sorted by most recently opened
    func getRecentFolders() -> [RecentFolder] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let folders = try? JSONDecoder().decode([RecentFolder].self, from: data) else {
            return []
        }
        return folders.sorted { $0.dateOpened > $1.dateOpened }
    }

    /// Add a folder to recents (creates security-scoped bookmark)
    func addFolder(_ url: URL) {
        // Create security-scoped bookmark
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        let newFolder = RecentFolder(url: url, bookmarkData: bookmarkData)

        var folders = getRecentFolders()

        // Remove existing entry for same path
        folders.removeAll { $0.path == url.path }

        // Add new entry at the beginning
        folders.insert(newFolder, at: 0)

        // Trim to max
        if folders.count > maxRecents {
            folders = Array(folders.prefix(maxRecents))
        }

        save(folders)
    }

    /// Remove a folder from recents
    func removeFolder(_ folder: RecentFolder) {
        var folders = getRecentFolders()
        folders.removeAll { $0.id == folder.id }
        save(folders)
    }

    /// Resolve a bookmark to get a usable URL (starts security scope)
    func resolveBookmark(_ folder: RecentFolder) -> URL? {
        var isStale = false

        guard let url = try? URL(
            resolvingBookmarkData: folder.bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }

        // If bookmark is stale, update it
        if isStale {
            addFolder(url)
        }

        return url
    }

    /// Clear all recent folders
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Private

    private func save(_ folders: [RecentFolder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
