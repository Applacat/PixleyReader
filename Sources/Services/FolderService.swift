import Foundation
import os.log

private let logger = Logger(subsystem: "com.aimd.reader", category: "FolderService")

// MARK: - Cached Folder Item

/// Cached representation of a folder tree with modification dates for diffing
struct CachedFolder: Codable {
    let path: String
    let modificationDate: Date
    let items: [CachedItem]
}

struct CachedItem: Codable {
    let path: String
    let name: String
    let isFolder: Bool
    let markdownCount: Int
    let modificationDate: Date?
    let children: [CachedItem]?
}

// MARK: - Folder Service

/// Service for loading folder contents and counting markdown files.
@MainActor
final class FolderService {

    static let shared = FolderService()

    private var cache: [String: CachedFolder] = [:]

    private init() {
        loadCacheFromDisk()
    }

    // MARK: - Cache Management

    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
            .appendingPathComponent("folder_cache.json")
    }

    private func loadCacheFromDisk() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode([String: CachedFolder].self, from: data) else {
            return
        }
        cache = cached
        logger.debug("Loaded cache with \(cached.count) folders")
    }

    private func saveCacheToDisk() {
        guard let url = cacheFileURL else { return }

        // Ensure directory exists
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url)

            // Exclude from backup - this is regenerable cache data
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(resourceValues)
        }
    }

    func clearCache() {
        cache.removeAll()
        if let url = cacheFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Invalidate cache for a specific folder and all its ancestors.
    /// This ensures markdown counts stay accurate when files change in subfolders.
    func invalidateCache(for url: URL) {
        var currentURL = url
        var invalidatedCount = 0

        // Invalidate the target folder
        if cache.removeValue(forKey: currentURL.path) != nil {
            invalidatedCount += 1
        }

        // Invalidate all ancestor folders (they contain stale markdown counts)
        while true {
            let parent = currentURL.deletingLastPathComponent()
            // Stop at root or when we've gone too far
            if parent.path == currentURL.path || parent.path == "/" {
                break
            }
            if cache.removeValue(forKey: parent.path) != nil {
                invalidatedCount += 1
            }
            currentURL = parent
        }

        if invalidatedCount > 0 {
            logger.debug("Invalidated \(invalidatedCount) cache entries for \(url.lastPathComponent) and ancestors")
            saveCacheToDisk()
        }
    }

    /// Invalidate cache for a specific folder only, without affecting ancestors.
    /// Use this for targeted invalidation when you know parent counts aren't affected.
    func invalidateCacheForSingleFolder(at url: URL) {
        if cache.removeValue(forKey: url.path) != nil {
            saveCacheToDisk()
        }
    }

    // MARK: - Load Tree

    /// Load entire folder tree recursively for hierarchical List (with caching)
    func loadTree(at url: URL) async -> [FolderItem] {
        let path = url.path
        let modDate = Self.getModificationDate(for: url)

        // Check cache
        if let cached = cache[path], cached.modificationDate == modDate {
            logger.debug("Cache hit for \(url.lastPathComponent)")
            return convertCachedItems(cached.items, baseURL: url)
        }

        // Cache miss - full scan
        logger.debug("Cache miss for \(url.lastPathComponent), scanning...")
        let items = await Task.detached(priority: .userInitiated) {
            Self.loadTreeSync(at: url)
        }.value

        // Save to cache
        let cachedItems = convertCachedItems(items)
        cache[path] = CachedFolder(path: path, modificationDate: modDate ?? Date.distantPast, items: cachedItems)
        saveCacheToDisk()

        return items
    }

    /// Load with smart diff - only rescan modified folders
    func loadTreeWithDiff(at url: URL) async -> [FolderItem] {
        let path = url.path
        let modDate = Self.getModificationDate(for: url)

        // Check if root folder changed
        if let cached = cache[path], cached.modificationDate == modDate {
            // Root unchanged - check children for changes
            logger.debug("Root unchanged, checking children...")
            let cachedItems = cached.items
            let items = await Task.detached(priority: .userInitiated) {
                Self.loadTreeWithDiffSync(at: url, cached: cachedItems)
            }.value

            // Update cache
            let newCachedItems = convertCachedItems(items)
            cache[path] = CachedFolder(path: path, modificationDate: modDate ?? Date.distantPast, items: newCachedItems)
            saveCacheToDisk()

            return items
        }

        // Root changed - full rescan
        return await loadTree(at: url)
    }

    private nonisolated static func loadTreeWithDiffSync(at url: URL, cached: [CachedItem]) -> [FolderItem] {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey]
        ) else {
            return []
        }

        // Build lookup for cached items
        let cachedByPath = Dictionary(uniqueKeysWithValues: cached.map { ($0.path, $0) })

        var items: [FolderItem] = []

        for itemURL in contents {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isHiddenKey])
            if resourceValues?.isHidden == true { continue }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) else { continue }

            let isFolder = isDirectory.boolValue
            let itemPath = itemURL.path
            let itemModDate = Self.getModificationDateSync(for: itemURL)

            if isFolder {
                // Check if folder is cached and unchanged
                if let cachedItem = cachedByPath[itemPath],
                   let cachedChildren = cachedItem.children,
                   cachedItem.modificationDate == itemModDate {
                    // Use cached - recursively check children
                    let children = Self.loadTreeWithDiffSync(at: itemURL, cached: cachedChildren)
                    // Recompute count from children (they may have changed)
                    let mdCount = children.reduce(0) { $0 + $1.markdownCount }
                    let item = FolderItem(url: itemURL, isFolder: true, markdownCount: mdCount, children: children)
                    items.append(item)
                } else {
                    // Changed - full rescan of this subtree
                    let children = Self.loadTreeSync(at: itemURL)
                    let mdCount = children.reduce(0) { $0 + $1.markdownCount }
                    let item = FolderItem(url: itemURL, isFolder: true, markdownCount: mdCount, children: children)
                    items.append(item)
                }
            } else {
                // Files: count is 1 if markdown, 0 otherwise
                let ext = itemURL.pathExtension.lowercased()
                let isMarkdown = (ext == "md" || ext == "markdown")
                let item = FolderItem(url: itemURL, isFolder: false, markdownCount: isMarkdown ? 1 : 0)
                items.append(item)
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private nonisolated static func loadTreeSync(at url: URL) -> [FolderItem] {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey]
        ) else {
            return []
        }

        var items: [FolderItem] = []

        for itemURL in contents {
            // Skip hidden files
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isHiddenKey])
            if resourceValues?.isHidden == true { continue }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) else { continue }

            let isFolder = isDirectory.boolValue

            if isFolder {
                // Recursively load children first
                let children = Self.loadTreeSync(at: itemURL)
                // OOD: FolderItem structure naturally aggregates children's markdown counts
                // The tree hierarchy makes this computation self-evident
                let mdCount = children.reduce(0) { $0 + $1.markdownCount }
                let item = FolderItem(url: itemURL, isFolder: true, markdownCount: mdCount, children: children)
                items.append(item)
            } else {
                // Files: count is 1 if markdown, 0 otherwise
                let ext = itemURL.pathExtension.lowercased()
                let isMarkdown = (ext == "md" || ext == "markdown")
                let item = FolderItem(url: itemURL, isFolder: false, markdownCount: isMarkdown ? 1 : 0)
                items.append(item)
            }
        }

        // Sort: folders first, then alphabetically
        return items.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Cache Conversion

    private nonisolated static func getModificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private nonisolated static func getModificationDateSync(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func convertCachedItems(_ items: [FolderItem]) -> [CachedItem] {
        items.map { item in
            CachedItem(
                path: item.url.path,
                name: item.name,
                isFolder: item.isFolder,
                markdownCount: item.markdownCount,
                modificationDate: Self.getModificationDate(for: item.url),
                children: item.children.map { convertCachedItems($0) }
            )
        }
    }

    private func convertCachedItems(_ cached: [CachedItem], baseURL: URL) -> [FolderItem] {
        cached.map { item in
            let url = URL(fileURLWithPath: item.path)
            return FolderItem(
                url: url,
                isFolder: item.isFolder,
                markdownCount: item.markdownCount,
                children: item.children.map { convertCachedItems($0, baseURL: url) }
            )
        }
    }
}
