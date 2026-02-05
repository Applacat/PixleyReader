import Foundation

// MARK: - Folder Tree Filter

/// Utility for filtering folder trees to show only markdown files.
/// Extracted from ContentView for testability.
struct FolderTreeFilter {

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
