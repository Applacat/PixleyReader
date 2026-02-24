import Foundation
import os.log

private let log = Logger(subsystem: "com.aimd.reader", category: "RecentFoldersManager")

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
/// Data stored as JSON files in Application Support/AIMDReader/.
/// Migrates legacy UserDefaults data on first access.
@MainActor
final class RecentFoldersManager {

    static let shared = RecentFoldersManager()

    private let maxRecents = 10
    private let maxRecentFiles = 4

    // Legacy UserDefaults keys (for migration)
    private let legacyFoldersKey = "recentFolders"
    private let legacyFilesKey = "recentFiles"

    // In-memory caches — loaded once from disk, invalidated on mutation
    private var cachedFolders: [RecentFolder]?
    private var cachedFiles: [RecentItem]?

    private init() {}

    // MARK: - Storage Paths

    private var storageDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
    }

    private var recentFoldersFileURL: URL? {
        storageDirectory?.appendingPathComponent("RecentFolders.json")
    }

    private var recentFilesFileURL: URL? {
        storageDirectory?.appendingPathComponent("RecentFiles.json")
    }

    /// Ensures the storage directory exists and writes data with protection.
    private func writeToFile(_ data: Data, at url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Set backup exclusion before write (effective if file already exists)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)

        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            log.error("Failed to write to \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }

        // Re-apply backup exclusion for newly created files
        try? mutableURL.setResourceValues(resourceValues)
    }

    // MARK: - Public API

    /// Get list of recent folders, sorted by most recently opened.
    /// Uses in-memory cache after first load to avoid repeated disk I/O on @MainActor.
    func getRecentFolders() -> [RecentFolder] {
        if let cached = cachedFolders { return cached }

        let loaded = loadFoldersFromDisk()
        cachedFolders = loaded
        return loaded
    }

    /// Loads folders from disk (called once per app session, or after cache invalidation).
    private func loadFoldersFromDisk() -> [RecentFolder] {
        // Try file storage first
        if let fileURL = recentFoldersFileURL,
           let data = try? Data(contentsOf: fileURL) {
            do {
                let folders = try JSONDecoder().decode([RecentFolder].self, from: data)
                return folders.sorted { $0.dateOpened > $1.dateOpened }
            } catch {
                log.error("Failed to decode RecentFolders.json: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: fileURL)
                return []
            }
        }

        // Try legacy UserDefaults migration
        if let data = UserDefaults.standard.data(forKey: legacyFoldersKey) {
            do {
                let folders = try JSONDecoder().decode([RecentFolder].self, from: data)
                saveFolders(folders)
                UserDefaults.standard.removeObject(forKey: legacyFoldersKey)
                log.info("Migrated \(folders.count) recent folders from UserDefaults to file storage")
                return folders.sorted { $0.dateOpened > $1.dateOpened }
            } catch {
                log.error("Failed to decode legacy recent folders: \(error.localizedDescription)")
                UserDefaults.standard.removeObject(forKey: legacyFoldersKey)
            }
        }

        return []
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

        saveFolders(folders)
    }

    /// Remove a folder from recents
    func removeFolder(_ folder: RecentFolder) {
        var folders = getRecentFolders()
        folders.removeAll { $0.id == folder.id }
        saveFolders(folders)
    }

    /// Remove a folder from recents by path
    func removeFolderByPath(_ path: String) {
        var folders = getRecentFolders()
        folders.removeAll { $0.path == path }
        saveFolders(folders)
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
        saveFolders(folders)
    }

    /// Clear all recent folders and files
    func clearAll() {
        cachedFolders = []
        cachedFiles = []
        if let foldersURL = recentFoldersFileURL {
            try? FileManager.default.removeItem(at: foldersURL)
        }
        if let filesURL = recentFilesFileURL {
            try? FileManager.default.removeItem(at: filesURL)
        }
        // Clean up legacy keys
        UserDefaults.standard.removeObject(forKey: legacyFoldersKey)
        UserDefaults.standard.removeObject(forKey: legacyFilesKey)
    }

    // MARK: - Session Restore

    /// Returns the most recently opened folder for session restore.
    /// This is the folder to reopen when the app launches.
    func lastSessionFolder() -> RecentFolder? {
        getRecentFolders().first
    }

    /// Returns the most recently opened file within a given folder for session restore.
    func lastSessionFile(forFolderPath folderPath: String) -> URL? {
        let files = getRecentFiles()
        guard let match = files.first(where: { $0.parentPath == folderPath }) else {
            return nil
        }
        let url = URL(fileURLWithPath: match.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    // MARK: - Recent Files

    /// Get list of recent files, sorted by most recently opened.
    /// Uses in-memory cache after first load to avoid repeated disk I/O on @MainActor.
    func getRecentFiles() -> [RecentItem] {
        if let cached = cachedFiles { return cached }

        let loaded = loadFilesFromDisk()
        cachedFiles = loaded
        return loaded
    }

    /// Loads files from disk (called once per app session, or after cache invalidation).
    private func loadFilesFromDisk() -> [RecentItem] {
        // Try file storage first
        if let fileURL = recentFilesFileURL,
           let data = try? Data(contentsOf: fileURL) {
            do {
                let files = try JSONDecoder().decode([RecentItem].self, from: data)
                return files.sorted { $0.dateOpened > $1.dateOpened }
            } catch {
                log.error("Failed to decode RecentFiles.json: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: fileURL)
                return []
            }
        }

        // Try legacy UserDefaults migration
        if let data = UserDefaults.standard.data(forKey: legacyFilesKey) {
            do {
                let files = try JSONDecoder().decode([RecentItem].self, from: data)
                saveFiles(files)
                UserDefaults.standard.removeObject(forKey: legacyFilesKey)
                log.info("Migrated \(files.count) recent files from UserDefaults to file storage")
                return files.sorted { $0.dateOpened > $1.dateOpened }
            } catch {
                log.error("Failed to decode legacy recent files: \(error.localizedDescription)")
                UserDefaults.standard.removeObject(forKey: legacyFilesKey)
            }
        }

        return []
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

    // MARK: - Private Storage

    private func saveFiles(_ files: [RecentItem]) {
        guard let fileURL = recentFilesFileURL else { return }
        cachedFiles = files.sorted { $0.dateOpened > $1.dateOpened }
        do {
            let data = try JSONEncoder().encode(files)
            writeToFile(data, at: fileURL)
        } catch {
            log.error("Failed to encode recent files: \(error.localizedDescription)")
        }
    }

    private func saveFolders(_ folders: [RecentFolder]) {
        guard let fileURL = recentFoldersFileURL else { return }
        cachedFolders = folders.sorted { $0.dateOpened > $1.dateOpened }
        do {
            let data = try JSONEncoder().encode(folders)
            writeToFile(data, at: fileURL)
        } catch {
            log.error("Failed to encode recent folders: \(error.localizedDescription)")
        }
    }
}
