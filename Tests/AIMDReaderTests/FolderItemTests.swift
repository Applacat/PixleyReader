import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// Since FolderItem is in the main app (executable target),
// we mirror the implementation here for testing the logic.

// MARK: - FolderItem Mirror

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

// MARK: - Tests

final class FolderItemTests: XCTestCase {

    // MARK: - isMarkdown Tests

    func testMdExtension_isMarkdown() {
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/readme.md"), isFolder: false)
        XCTAssertTrue(item.isMarkdown)
    }

    func testMarkdownExtension_isMarkdown() {
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/readme.markdown"), isFolder: false)
        XCTAssertTrue(item.isMarkdown)
    }

    func testTxtExtension_isNotMarkdown() {
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/readme.txt"), isFolder: false)
        XCTAssertFalse(item.isMarkdown)
    }

    func testFolder_isNotMarkdown() {
        // Even if folder name ends in .md
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/notes.md"), isFolder: true)
        XCTAssertFalse(item.isMarkdown)
    }

    func testCaseInsensitive_MD_isMarkdown() {
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/readme.MD"), isFolder: false)
        XCTAssertTrue(item.isMarkdown)
    }

    func testCaseInsensitive_Markdown_isMarkdown() {
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/readme.Markdown"), isFolder: false)
        XCTAssertTrue(item.isMarkdown)
    }

    func testSwiftExtension_isNotMarkdown() {
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/file.swift"), isFolder: false)
        XCTAssertFalse(item.isMarkdown)
    }

    func testNoExtension_isNotMarkdown() {
        let item = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/README"), isFolder: false)
        XCTAssertFalse(item.isMarkdown)
    }

    // MARK: - Children Tests

    func testChildren_populatedForFolders() {
        let child = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/folder/file.md"), isFolder: false)
        let folder = TestableFolderItem(url: URL(fileURLWithPath: "/tmp/folder"), isFolder: true, children: [child])
        XCTAssertNotNil(folder.children)
        XCTAssertEqual(folder.children?.count, 1)
        XCTAssertEqual(folder.children?.first?.name, "file.md")
    }
}
