import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// These mirror the production types for testing purposes since
// the main app is an executable target and can't be imported.

/// Test version of FolderItem
private struct FolderItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isFolder: Bool
    let isMarkdown: Bool
    let markdownCount: Int
    var children: [FolderItem]?

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

/// Test version of FolderTreeFilter
private struct FolderTreeFilter {

    static func filterMarkdownOnly(_ items: [FolderItem]) -> [FolderItem] {
        items.compactMap { item in
            if item.isFolder {
                let filteredChildren = filterMarkdownOnly(item.children ?? [])
                if filteredChildren.isEmpty {
                    return nil
                }
                return FolderItem(
                    url: item.url,
                    isFolder: true,
                    markdownCount: filteredChildren.reduce(0) { $0 + $1.markdownCount },
                    children: filteredChildren
                )
            } else {
                return item.isMarkdown ? item : nil
            }
        }
    }

    static func filterByName(_ items: [FolderItem], query: String) -> [FolderItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }

        return items.compactMap { item in
            if item.isFolder {
                let filteredChildren = filterByName(item.children ?? [], query: trimmed)
                if filteredChildren.isEmpty { return nil }
                return FolderItem(
                    url: item.url,
                    isFolder: true,
                    markdownCount: filteredChildren.reduce(0) { $0 + $1.markdownCount },
                    children: filteredChildren
                )
            } else {
                return item.name.localizedCaseInsensitiveContains(trimmed) ? item : nil
            }
        }
    }

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

    static func findFirstMarkdown(in items: [FolderItem]) -> FolderItem? {
        for item in items {
            if item.isMarkdown {
                return item
            }
            if let children = item.children,
               let found = findFirstMarkdown(in: children) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Tests

final class FolderTreeFilterTests: XCTestCase {

    // MARK: - Test Data Helpers

    private func makeFile(_ name: String, isMarkdown: Bool = false) -> FolderItem {
        let ext = isMarkdown ? ".md" : ".txt"
        let url = URL(fileURLWithPath: "/test/\(name)\(ext)")
        return FolderItem(url: url, isFolder: false, markdownCount: isMarkdown ? 1 : 0)
    }

    private func makeFolder(_ name: String, children: [FolderItem]) -> FolderItem {
        let url = URL(fileURLWithPath: "/test/\(name)")
        let mdCount = children.reduce(0) { $0 + $1.markdownCount }
        return FolderItem(url: url, isFolder: true, markdownCount: mdCount, children: children)
    }

    // MARK: - filterMarkdownOnly Tests

    func testFiltersCorrectly_keepsOnlyMarkdown() {
        // Given: Mix of markdown and non-markdown files
        let items = [
            makeFile("readme", isMarkdown: true),
            makeFile("config", isMarkdown: false),
            makeFile("notes", isMarkdown: true),
            makeFile("data", isMarkdown: false)
        ]

        // When: Filter for markdown only
        let result = FolderTreeFilter.filterMarkdownOnly(items)

        // Then: Only markdown files remain
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.isMarkdown })
        XCTAssertTrue(result.map { $0.name }.contains("readme.md"))
        XCTAssertTrue(result.map { $0.name }.contains("notes.md"))
    }

    func testEdgeCase_emptyFolderReturnsEmpty() {
        // Given: Empty folder
        let items: [FolderItem] = []

        // When: Filter
        let result = FolderTreeFilter.filterMarkdownOnly(items)

        // Then: Empty result
        XCTAssertTrue(result.isEmpty)
    }

    func testEdgeCase_nilChildrenHandled() {
        // Given: Folder with nil children (shouldn't happen but defensive)
        let folder = FolderItem(
            url: URL(fileURLWithPath: "/test/folder"),
            isFolder: true,
            markdownCount: 0,
            children: nil
        )
        let items = [folder]

        // When: Filter
        let result = FolderTreeFilter.filterMarkdownOnly(items)

        // Then: Empty folder is removed
        XCTAssertTrue(result.isEmpty)
    }

    func testNestedFolders_preservesStructureWithMarkdown() {
        // Given: Nested folder structure
        let deepFile = makeFile("deep", isMarkdown: true)
        let innerFolder = makeFolder("inner", children: [deepFile])
        let outerFolder = makeFolder("outer", children: [innerFolder])
        let items = [outerFolder]

        // When: Filter
        let result = FolderTreeFilter.filterMarkdownOnly(items)

        // Then: Structure preserved
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isFolder)
        XCTAssertEqual(result[0].children?.count, 1)
        XCTAssertEqual(result[0].children?[0].children?.count, 1)
        XCTAssertEqual(result[0].children?[0].children?[0].isMarkdown, true)
    }

    func testEmptyNestedFolders_removed() {
        // Given: Folder with only non-markdown files
        let txtFile = makeFile("notes", isMarkdown: false)
        let folder = makeFolder("docs", children: [txtFile])
        let items = [folder]

        // When: Filter
        let result = FolderTreeFilter.filterMarkdownOnly(items)

        // Then: Empty folder removed
        XCTAssertTrue(result.isEmpty)
    }

    func testMarkdownCount_recalculatedAfterFiltering() {
        // Given: Folder with mixed content
        let md1 = makeFile("doc1", isMarkdown: true)
        let md2 = makeFile("doc2", isMarkdown: true)
        let txt = makeFile("config", isMarkdown: false)
        let folder = makeFolder("docs", children: [md1, md2, txt])
        let items = [folder]

        // When: Filter
        let result = FolderTreeFilter.filterMarkdownOnly(items)

        // Then: Markdown count is correct (2, not 3)
        XCTAssertEqual(result[0].markdownCount, 2)
        XCTAssertEqual(result[0].children?.count, 2)
    }

    // MARK: - findFirstMarkdown Tests

    func testFindsFirstMarkdown_returnsFirstInList() {
        // Given: Multiple markdown files
        let items = [
            makeFile("first", isMarkdown: true),
            makeFile("second", isMarkdown: true)
        ]

        // When: Find first
        let result = FolderTreeFilter.findFirstMarkdown(in: items)

        // Then: Returns first one
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "first.md")
    }

    func testFindsFirstMarkdown_searchesNestedFolders() {
        // Given: Markdown only in nested folder
        let deepFile = makeFile("nested", isMarkdown: true)
        let folder = makeFolder("docs", children: [deepFile])
        let items = [folder]

        // When: Find first
        let result = FolderTreeFilter.findFirstMarkdown(in: items)

        // Then: Finds nested file
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "nested.md")
    }

    func testFindsFirstMarkdown_depthFirstOrder() {
        // Given: Markdown at root and in folder
        let rootFile = makeFile("root", isMarkdown: true)
        let nestedFile = makeFile("nested", isMarkdown: true)
        let folder = makeFolder("docs", children: [nestedFile])
        let items = [folder, rootFile]

        // When: Find first (depth-first, so folder checked first)
        let result = FolderTreeFilter.findFirstMarkdown(in: items)

        // Then: Returns first encountered (nested due to depth-first)
        XCTAssertNotNil(result)
        // Depth-first means folder is searched first
        XCTAssertEqual(result?.name, "nested.md")
    }

    func testFindsFirstMarkdown_returnsNilForNoMarkdown() {
        // Given: Only non-markdown files
        let items = [
            makeFile("config", isMarkdown: false),
            makeFile("data", isMarkdown: false)
        ]

        // When: Find first
        let result = FolderTreeFilter.findFirstMarkdown(in: items)

        // Then: Returns nil
        XCTAssertNil(result)
    }

    func testFindsFirstMarkdown_handlesEmptyList() {
        // Given: Empty list
        let items: [FolderItem] = []

        // When: Find first
        let result = FolderTreeFilter.findFirstMarkdown(in: items)

        // Then: Returns nil
        XCTAssertNil(result)
    }

    // MARK: - filterByName Tests

    func testFilterByName_matchesPartialFilename() {
        // Given: Files with various names
        let items = [
            makeFile("readme", isMarkdown: true),
            makeFile("changelog", isMarkdown: true),
            makeFile("config", isMarkdown: false)
        ]

        // When: Filter with partial match
        let result = FolderTreeFilter.filterByName(items, query: "read")

        // Then: Only matching file returned
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "readme.md")
    }

    func testFilterByName_caseInsensitive() {
        // Given: File with mixed case name
        let items = [
            makeFile("README", isMarkdown: true),
            makeFile("notes", isMarkdown: true)
        ]

        // When: Filter with lowercase query
        let result = FolderTreeFilter.filterByName(items, query: "readme")

        // Then: Matches regardless of case
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "README.md")
    }

    func testFilterByName_preservesParentFolders() {
        // Given: Nested structure with matching file
        let deepFile = makeFile("readme", isMarkdown: true)
        let otherFile = makeFile("config", isMarkdown: false)
        let folder = makeFolder("docs", children: [deepFile, otherFile])
        let items = [folder]

        // When: Filter for readme
        let result = FolderTreeFilter.filterByName(items, query: "readme")

        // Then: Parent folder preserved
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isFolder)
        XCTAssertEqual(result[0].children?.count, 1)
        XCTAssertEqual(result[0].children?[0].name, "readme.md")
    }

    func testFilterByName_emptyQueryReturnsAll() {
        // Given: Some files
        let items = [
            makeFile("readme", isMarkdown: true),
            makeFile("notes", isMarkdown: true)
        ]

        // When: Filter with empty query
        let result = FolderTreeFilter.filterByName(items, query: "")

        // Then: All items returned unchanged
        XCTAssertEqual(result.count, items.count)
    }

    func testFilterByName_noMatchesReturnsEmpty() {
        // Given: Files that don't match
        let items = [
            makeFile("readme", isMarkdown: true),
            makeFile("notes", isMarkdown: true)
        ]

        // When: Filter with non-matching query
        let result = FolderTreeFilter.filterByName(items, query: "zebra")

        // Then: Empty result
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - flattenMarkdownFiles Tests

    func testFlattenMarkdownFiles_returnsAllMarkdownFiles() {
        // Given: Nested structure with markdown files
        let file1 = makeFile("doc1", isMarkdown: true)
        let file2 = makeFile("doc2", isMarkdown: true)
        let txt = makeFile("config", isMarkdown: false)
        let folder = makeFolder("docs", children: [file2, txt])
        let items = [file1, folder]

        // When: Flatten
        let result = FolderTreeFilter.flattenMarkdownFiles(items)

        // Then: All markdown files in depth-first order
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "doc1.md")
        XCTAssertEqual(result[1].name, "doc2.md")
    }

    func testFlattenMarkdownFiles_excludesFolders() {
        // Given: Folders and files
        let file = makeFile("readme", isMarkdown: true)
        let folder = makeFolder("docs", children: [file])
        let items = [folder]

        // When: Flatten
        let result = FolderTreeFilter.flattenMarkdownFiles(items)

        // Then: Only files, no folders
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isFolder)
    }

    func testFlattenMarkdownFiles_handlesEmptyTree() {
        // Given: Empty tree
        let items: [FolderItem] = []

        // When: Flatten
        let result = FolderTreeFilter.flattenMarkdownFiles(items)

        // Then: Empty result
        XCTAssertTrue(result.isEmpty)
    }
}
