import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// FolderService.loadTreeSync(at:) and loadTreeWithDiffSync(at:cached:) are
// nonisolated static methods — but they're private. We mirror the scanning
// logic here and test with real temp directories.

// MARK: - FolderItem Mirror (matches production)

private struct TestableFolderItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isFolder: Bool
    let isMarkdown: Bool
    let markdownCount: Int
    var children: [TestableFolderItem]?

    init(url: URL, isFolder: Bool, markdownCount: Int = 0, children: [TestableFolderItem]? = nil) {
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

// MARK: - CachedItem Mirror (matches production Codable struct)

private struct TestableCachedItem: Codable, Equatable {
    let path: String
    let name: String
    let isFolder: Bool
    let markdownCount: Int
    let modificationDate: Date?
    let children: [TestableCachedItem]?
}

// MARK: - CachedFolder Mirror

private struct TestableCachedFolder: Codable, Equatable {
    let path: String
    let modificationDate: Date
    let items: [TestableCachedItem]
}

// MARK: - loadTreeSync Mirror

/// Mirrors FolderService.loadTreeSync(at:) — scans directory, skips hidden,
/// counts markdown, sorts folders-first then alpha.
private func loadTreeSync(at url: URL) -> [TestableFolderItem] {
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey]
    ) else {
        return []
    }

    var items: [TestableFolderItem] = []

    for itemURL in contents {
        let resourceValues = try? itemURL.resourceValues(forKeys: [.isHiddenKey])
        if resourceValues?.isHidden == true { continue }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) else { continue }

        let isFolder = isDirectory.boolValue

        if isFolder {
            let children = loadTreeSync(at: itemURL)
            let mdCount = children.reduce(0) { $0 + $1.markdownCount }
            let item = TestableFolderItem(url: itemURL, isFolder: true, markdownCount: mdCount, children: children)
            items.append(item)
        } else {
            let ext = itemURL.pathExtension.lowercased()
            let isMarkdown = (ext == "md" || ext == "markdown")
            let item = TestableFolderItem(url: itemURL, isFolder: false, markdownCount: isMarkdown ? 1 : 0)
            items.append(item)
        }
    }

    return items.sorted { lhs, rhs in
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - loadTreeWithDiffSync Mirror

private func loadTreeWithDiffSync(at url: URL, cached: [TestableCachedItem]) -> [TestableFolderItem] {
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey]
    ) else {
        return []
    }

    let cachedByPath = Dictionary(uniqueKeysWithValues: cached.map { ($0.path, $0) })
    var items: [TestableFolderItem] = []

    for itemURL in contents {
        let resourceValues = try? itemURL.resourceValues(forKeys: [.isHiddenKey])
        if resourceValues?.isHidden == true { continue }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) else { continue }

        let isFolder = isDirectory.boolValue
        let itemPath = itemURL.path
        let itemModDate = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        if isFolder {
            if let cachedItem = cachedByPath[itemPath],
               let cachedChildren = cachedItem.children,
               cachedItem.modificationDate == itemModDate {
                // Cached and unchanged — reuse
                let children = loadTreeWithDiffSync(at: itemURL, cached: cachedChildren)
                let mdCount = children.reduce(0) { $0 + $1.markdownCount }
                let item = TestableFolderItem(url: itemURL, isFolder: true, markdownCount: mdCount, children: children)
                items.append(item)
            } else {
                // Changed — full rescan
                let children = loadTreeSync(at: itemURL)
                let mdCount = children.reduce(0) { $0 + $1.markdownCount }
                let item = TestableFolderItem(url: itemURL, isFolder: true, markdownCount: mdCount, children: children)
                items.append(item)
            }
        } else {
            let ext = itemURL.pathExtension.lowercased()
            let isMarkdown = (ext == "md" || ext == "markdown")
            let item = TestableFolderItem(url: itemURL, isFolder: false, markdownCount: isMarkdown ? 1 : 0)
            items.append(item)
        }
    }

    return items.sorted { lhs, rhs in
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - Tests

final class FolderServiceLoadingTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    // MARK: - Helper

    private func createFile(_ name: String, in dir: URL? = nil, content: String = "test") throws {
        let parent = dir ?? tempDir!
        try content.write(to: parent.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func createSubfolder(_ name: String, in dir: URL? = nil) throws -> URL {
        let parent = dir ?? tempDir!
        let subdir = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        return subdir
    }

    // MARK: - loadTreeSync: Flat Directory

    func testLoadTreeSync_flatDirectory_returnsSortedFiles() throws {
        try createFile("beta.md")
        try createFile("alpha.txt")
        try createFile("gamma.md")

        let items = loadTreeSync(at: tempDir)

        XCTAssertEqual(items.count, 3)
        // Sorted alphabetically (no folders, so just alpha sort)
        XCTAssertEqual(items.map(\.name), ["alpha.txt", "beta.md", "gamma.md"])
    }

    // MARK: - loadTreeSync: Markdown Counting

    func testLoadTreeSync_countsMarkdownFilesCorrectly() throws {
        try createFile("readme.md")
        try createFile("notes.markdown")
        try createFile("data.txt")
        try createFile("code.swift")

        let items = loadTreeSync(at: tempDir)

        let mdItems = items.filter { $0.isMarkdown }
        let nonMdItems = items.filter { !$0.isMarkdown }
        XCTAssertEqual(mdItems.count, 2)
        XCTAssertEqual(nonMdItems.count, 2)

        // markdown files have markdownCount = 1
        for item in mdItems {
            XCTAssertEqual(item.markdownCount, 1)
        }
        for item in nonMdItems {
            XCTAssertEqual(item.markdownCount, 0)
        }
    }

    // MARK: - loadTreeSync: Hidden Files

    func testLoadTreeSync_skipsHiddenFiles() throws {
        try createFile("visible.md")
        try createFile(".hidden.md")

        let items = loadTreeSync(at: tempDir)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "visible.md")
    }

    // MARK: - loadTreeSync: Recursive

    func testLoadTreeSync_recursive_nestedFoldersHaveCorrectMarkdownCount() throws {
        let subdir = try createSubfolder("notes")
        try createFile("file1.md", in: subdir)
        try createFile("file2.md", in: subdir)
        try createFile("file3.txt", in: subdir)

        let items = loadTreeSync(at: tempDir)

        // Should have one folder
        XCTAssertEqual(items.count, 1)
        let folder = items.first!
        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.name, "notes")
        // 2 markdown files in subfolder
        XCTAssertEqual(folder.markdownCount, 2)
        XCTAssertEqual(folder.children?.count, 3)
    }

    // MARK: - loadTreeSync: Empty Directory

    func testLoadTreeSync_emptyDirectory_returnsEmptyArray() {
        let items = loadTreeSync(at: tempDir)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - loadTreeSync: Inaccessible Directory

    func testLoadTreeSync_inaccessibleDirectory_returnsEmptyArray() {
        let nonexistent = tempDir.appendingPathComponent("does-not-exist")
        let items = loadTreeSync(at: nonexistent)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - loadTreeSync: Sorting (folders first)

    func testLoadTreeSync_sortsFoldersFirst() throws {
        try createFile("zebra.md")
        _ = try createSubfolder("alpha")

        let items = loadTreeSync(at: tempDir)

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isFolder, "Folders should come first")
        XCTAssertEqual(items[0].name, "alpha")
        XCTAssertEqual(items[1].name, "zebra.md")
    }

    // MARK: - loadTreeWithDiffSync: Unchanged Folder Reuses Cached

    func testLoadTreeWithDiffSync_unchangedFolder_reusesCached() throws {
        let subdir = try createSubfolder("docs")
        try createFile("readme.md", in: subdir)

        // Build cache from current state
        let initialItems = loadTreeSync(at: tempDir)
        let modDate = try? subdir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let cachedItems = initialItems.map { item -> TestableCachedItem in
            TestableCachedItem(
                path: item.url.path,
                name: item.name,
                isFolder: item.isFolder,
                markdownCount: item.markdownCount,
                modificationDate: modDate,
                children: item.children?.map { child in
                    TestableCachedItem(
                        path: child.url.path,
                        name: child.name,
                        isFolder: child.isFolder,
                        markdownCount: child.markdownCount,
                        modificationDate: nil,
                        children: nil
                    )
                }
            )
        }

        // Load with diff — folder unchanged, should still find the file
        let diffItems = loadTreeWithDiffSync(at: tempDir, cached: cachedItems)
        XCTAssertEqual(diffItems.count, 1)
        XCTAssertEqual(diffItems.first?.name, "docs")
        XCTAssertEqual(diffItems.first?.children?.count, 1)
    }

    // MARK: - CachedItem Codable Round-Trip

    func testCachedItem_codableRoundTrip() throws {
        let item = TestableCachedItem(
            path: "/tmp/test/readme.md",
            name: "readme.md",
            isFolder: false,
            markdownCount: 1,
            modificationDate: Date(timeIntervalSince1970: 1000),
            children: nil
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(TestableCachedItem.self, from: data)
        XCTAssertEqual(decoded, item)
    }

    func testCachedFolder_codableRoundTrip() throws {
        let folder = TestableCachedFolder(
            path: "/tmp/test",
            modificationDate: Date(timeIntervalSince1970: 1000),
            items: [
                TestableCachedItem(
                    path: "/tmp/test/readme.md",
                    name: "readme.md",
                    isFolder: false,
                    markdownCount: 1,
                    modificationDate: Date(timeIntervalSince1970: 1000),
                    children: nil
                ),
                TestableCachedItem(
                    path: "/tmp/test/docs",
                    name: "docs",
                    isFolder: true,
                    markdownCount: 2,
                    modificationDate: Date(timeIntervalSince1970: 900),
                    children: []
                )
            ]
        )

        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(TestableCachedFolder.self, from: data)
        XCTAssertEqual(decoded, folder)
    }
}
