import Foundation

// MARK: - Folder Item

/// Represents a file or folder in the file browser.
/// Uses `children` for native SwiftUI hierarchical List support.
struct FolderItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isFolder: Bool
    let isMarkdown: Bool
    let markdownCount: Int
    var children: [FolderItem]?  // nil = file (leaf), populated = folder

    init(url: URL, isFolder: Bool, markdownCount: Int = 0, children: [FolderItem]? = nil) {
        self.id = url.path
        self.name = url.lastPathComponent
        self.url = url
        self.isFolder = isFolder
        self.markdownCount = markdownCount
        self.children = children

        let ext = url.pathExtension.lowercased()
        self.isMarkdown = !isFolder && (ext == "md" || ext == "markdown")
    }
}
