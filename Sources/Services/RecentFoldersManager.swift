import Foundation

// MARK: - Recent Item

/// A recently opened item (folder or file) with its security-scoped bookmark
struct RecentItem: Identifiable, Codable {
    let id: UUID
    let name: String
    let path: String
    let bookmarkData: Data
    let dateOpened: Date
    let isFolder: Bool
    let parentPath: String?  // For files, the folder they're in

    init(url: URL, bookmarkData: Data, isFolder: Bool, parentPath: String? = nil) {
        self.id = UUID()
        self.name = url.lastPathComponent
        self.path = url.path
        self.bookmarkData = bookmarkData
        self.dateOpened = Date()
        self.isFolder = isFolder
        self.parentPath = parentPath
    }
}

// MARK: - Recent Folder (Legacy compatibility)

/// A recently opened folder with its security-scoped bookmark
struct RecentFolder: Identifiable, Codable {
    let id: UUID
    let name: String
    let path: String
    let bookmarkData: Data
    let dateOpened: Date

    /// Creates a new recent folder entry
    init(url: URL, bookmarkData: Data) {
        self.id = UUID()
        self.name = url.lastPathComponent
        self.path = url.path
        self.bookmarkData = bookmarkData
        self.dateOpened = Date()
    }

    /// Creates a recent folder with all fields specified (used for in-place updates)
    init(id: UUID, name: String, path: String, bookmarkData: Data, dateOpened: Date) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.dateOpened = dateOpened
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

    /// Remove a folder from recents by path
    func removeFolderByPath(_ path: String) {
        var folders = getRecentFolders()
        folders.removeAll { $0.path == path }
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

        // Don't start security scope here - caller (AppState.setRootFolder) handles it
        // Just validate the URL exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        // If bookmark is stale, refresh it in-place (preserves order)
        if isStale {
            refreshStaleBookmark(folder, url: url)
        }

        return url
    }

    /// Refreshes a stale bookmark in-place without changing its position in the list.
    /// - Parameters:
    ///   - folder: The folder with the stale bookmark
    ///   - url: The resolved URL to create a new bookmark from
    private func refreshStaleBookmark(_ folder: RecentFolder, url: URL) {
        // Create fresh bookmark data
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        var folders = getRecentFolders()

        // Find the folder by its ID and update its bookmark in-place
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        // Create updated folder with same ID and dateOpened (preserves order)
        let updatedFolder = RecentFolder(
            id: folder.id,
            name: folder.name,
            path: folder.path,
            bookmarkData: bookmarkData,
            dateOpened: folder.dateOpened
        )

        folders[index] = updatedFolder
        save(folders)
    }

    /// Clear all recent folders
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
    }

    // MARK: - Session Restore

    /// Returns the most recently opened folder for session restore.
    /// This is the folder to reopen when the app launches.
    func lastSessionFolder() -> RecentFolder? {
        getRecentFolders().first
    }

    // MARK: - Recent Files

    private let recentFilesKey = "recentFiles"
    private let maxRecentFiles = 4

    /// Get list of recent files, sorted by most recently opened
    func getRecentFiles() -> [RecentItem] {
        guard let data = UserDefaults.standard.data(forKey: recentFilesKey),
              let files = try? JSONDecoder().decode([RecentItem].self, from: data) else {
            return []
        }
        return files.sorted { $0.dateOpened > $1.dateOpened }
    }

    /// Add a file to recents (called when user clicks a file in the tree)
    func addRecentFile(_ url: URL, parentFolder: URL?) {
        // Files inherit access from their parent folder, no separate bookmark needed
        // But we store the path for display
        let item = RecentItem(
            url: url,
            bookmarkData: Data(),  // Files use parent folder's security scope
            isFolder: false,
            parentPath: parentFolder?.path
        )

        var files = getRecentFiles()

        // Remove existing entry for same path
        files.removeAll { $0.path == url.path }

        // Add new entry at the beginning
        files.insert(item, at: 0)

        // Trim to max (4 recent files)
        if files.count > maxRecentFiles {
            files = Array(files.prefix(maxRecentFiles))
        }

        saveFiles(files)
    }

    /// Remove a file from recents
    func removeRecentFile(_ item: RecentItem) {
        var files = getRecentFiles()
        files.removeAll { $0.path == item.path }
        saveFiles(files)
    }

    /// Get combined recents (folders + files) for display
    func getAllRecents() -> [RecentItem] {
        let folders = getRecentFolders().map { folder in
            RecentItem(
                url: URL(fileURLWithPath: folder.path),
                bookmarkData: folder.bookmarkData,
                isFolder: true,
                parentPath: nil
            )
        }
        let files = getRecentFiles()

        // Combine and sort by date
        return (folders + files).sorted { $0.dateOpened > $1.dateOpened }
    }

    private func saveFiles(_ files: [RecentItem]) {
        guard let data = try? JSONEncoder().encode(files) else { return }
        UserDefaults.standard.set(data, forKey: recentFilesKey)
    }

    // MARK: - Private

    private func save(_ folders: [RecentFolder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
