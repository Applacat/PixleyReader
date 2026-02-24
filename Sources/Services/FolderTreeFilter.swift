import Foundation

// MARK: - Folder Tree Filter

/// Utility for filtering folder trees to show only markdown files.
/// Extracted from ContentView for testability.
struct FolderTreeFilter {

    /// Cache for filterByName results keyed by (rootPath, itemCount, query).
    /// Invalidated when the source items, root folder, or query change.
    @MainActor
    private static var nameFilterCache: (rootPath: String, itemCount: Int, query: String, result: [FolderItem])?

    // MARK: - Filter Markdown Only

    /// Filters a folder tree to only include markdown files and folders containing them.
    /// - Parameter items: The root items to filter
    /// - Returns: Filtered items containing only markdown files and their parent folders
    static func filterMarkdownOnly(_ items: [FolderItem]) -> [FolderItem] {
        items.compactMap { item in
            if item.isFolder {
                // Recursively filter children
                let filteredChildren = filterMarkdownOnly(item.children ?? [])

                // Only keep folder if it has markdown files
                if filteredChildren.isEmpty {
                    return nil
                }

                // Create new FolderItem with filtered children and updated count
                return FolderItem(
                    url: item.url,
                    isFolder: true,
                    markdownCount: filteredChildren.reduce(0) { $0 + $1.markdownCount },
                    children: filteredChildren
                )
            } else {
                // Only keep markdown files
                return item.isMarkdown ? item : nil
            }
        }
    }

    // MARK: - Filter By Name

    /// Filters a folder tree to items matching a search query by filename.
    /// - Parameters:
    ///   - items: The root items to filter
    ///   - query: Case-insensitive partial match on filename
    ///   - rootPath: Root folder path to disambiguate cache across different folders
    /// - Returns: Filtered items preserving parent folders of matches. Empty query returns items unchanged.
    @MainActor
    static func filterByName(_ items: [FolderItem], query: String, rootPath: String = "") -> [FolderItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }

        // Check cache (rootPath prevents stale results when switching folders)
        if let cached = nameFilterCache,
           cached.rootPath == rootPath,
           cached.itemCount == items.count,
           cached.query == trimmed {
            return cached.result
        }

        let result = _filterByName(items, query: trimmed)
        nameFilterCache = (rootPath: rootPath, itemCount: items.count, query: trimmed, result: result)
        return result
    }

    private static func _filterByName(_ items: [FolderItem], query: String) -> [FolderItem] {
        return items.compactMap { item in
            if item.isFolder {
                let filteredChildren = _filterByName(item.children ?? [], query: query)
                if filteredChildren.isEmpty { return nil }
                return FolderItem(
                    url: item.url,
                    isFolder: true,
                    markdownCount: filteredChildren.reduce(0) { $0 + $1.markdownCount },
                    children: filteredChildren
                )
            } else {
                // Case-insensitive partial match on filename
                return item.name.localizedCaseInsensitiveContains(query) ? item : nil
            }
        }
    }

    // MARK: - Flatten Markdown Files

    /// Flattens a folder tree into a flat list of all markdown files.
    /// - Parameter items: The root items to flatten
    /// - Returns: All markdown files from the tree, depth-first order
    static func flattenMarkdownFiles(_ items: [FolderItem]) -> [FolderItem] {
        var result: [FolderItem] = []
        for item in items {
            if item.isMarkdown {
                result.append(item)
            }
            if let children = item.children {
                result.append(contentsOf: flattenMarkdownFiles(children))
            }
        }
        return result
    }

    // MARK: - Find First Markdown

    /// Finds the first markdown file in a folder tree (depth-first).
    /// - Parameter items: The items to search
    /// - Returns: The first markdown file found, or nil if none exist
    static func findFirstMarkdown(in items: [FolderItem]) -> FolderItem? {
        for item in items {
            // Check if current item is markdown
            if item.isMarkdown {
                return item
            }

            // Recursively search children
            if let children = item.children,
               let found = findFirstMarkdown(in: children) {
                return found
            }
        }
        return nil
    }
}
