import Foundation
import os.log

private let logger = Logger(subsystem: "com.aimd.reader", category: "FolderService")

// MARK: - Cached Folder Item

/// Cached representation of a folder tree with modification dates for diffing
struct CachedFolder: Codable, Sendable {
    let path: String
    let modificationDate: Date
    let items: [CachedItem]
}

struct CachedItem: Codable, Sendable {
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
    private var cacheSaveTask: Task<Void, Never>?

    private init() {
        // Load cache asynchronously — [weak self] for pattern consistency
        // (singleton won't deallocate, but prevents copying this pattern to non-singletons)
        Task { [weak self] in
            await self?.loadCacheFromDisk()
        }
    }

    // MARK: - Cache Management

    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
            .appendingPathComponent("folder_cache.json")
    }

    private func loadCacheFromDisk() async {
        guard let url = cacheFileURL else { return }

        // Perform file I/O off main thread
        let loaded: [String: CachedFolder]? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let cached = try? JSONDecoder().decode([String: CachedFolder].self, from: data) else {
                return nil
            }
            return cached
        }.value

        if let cached = loaded {
            cache = cached
            logger.debug("Loaded cache with \(cached.count) folders")
        }
    }

    /// Schedules a debounced cache write (2-second delay).
    /// Multiple rapid invalidations coalesce into a single disk write.
    private func scheduleCacheSave() {
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveCacheToDisk()
        }
    }

    private func saveCacheToDisk() {
        guard let url = cacheFileURL else { return }
        let snapshot = cache

        Task.detached(priority: .utility) {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            guard let data = try? JSONEncoder().encode(snapshot) else { return }

            // Exclude from backup before write (effective if file already exists)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(resourceValues)

            try? data.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)

            // Re-apply for newly created files
            try? mutableURL.setResourceValues(resourceValues)
        }
    }

    /// Flushes any pending cache write immediately. Call on app termination.
    func flushCacheIfNeeded() {
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        saveCacheToDisk()
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
            scheduleCacheSave()
        }
    }

    /// Invalidate cache for a specific folder only, without affecting ancestors.
    /// Use this for targeted invalidation when you know parent counts aren't affected.
    func invalidateCacheForSingleFolder(at url: URL) {
        if cache.removeValue(forKey: url.path) != nil {
            scheduleCacheSave()
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
        scheduleCacheSave()

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
            scheduleCacheSave()

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
            if lhs.isFolder != rhs.isFolder { return rhs.isFolder }
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
            if lhs.isFolder != rhs.isFolder { return rhs.isFolder }
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
