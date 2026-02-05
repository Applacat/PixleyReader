import XCTest
@testable import aimdRenderer

final class DocumentModelTests: XCTestCase {

    func testEmptyDocument() {
        let doc = DocumentModel()
        XCTAssertTrue(doc.isEmpty)
        XCTAssertEqual(doc.lineCount, 0)
        XCTAssertTrue(doc.lines.isEmpty)
    }

    func testSingleLine() {
        let doc = DocumentModel(content: "Hello, World!")
        XCTAssertEqual(doc.lineCount, 1)
        XCTAssertEqual(doc.lines[0].number, 1)
        XCTAssertEqual(doc.lines[0].content, "Hello, World!")
    }

    func testMultiLine() {
        let content = """
        Line 1
        Line 2
        Line 3
        """
        let doc = DocumentModel(content: content)
        XCTAssertEqual(doc.lineCount, 3)
        XCTAssertEqual(doc.line(at: 1)?.content, "Line 1")
        XCTAssertEqual(doc.line(at: 2)?.content, "Line 2")
        XCTAssertEqual(doc.line(at: 3)?.content, "Line 3")
    }

    func testLineAccessOutOfBounds() {
        let doc = DocumentModel(content: "One line")
        XCTAssertNil(doc.line(at: 0))
        XCTAssertNil(doc.line(at: 2))
        XCTAssertNil(doc.line(at: -1))
    }

    func testLinesRange() {
        let content = "A\nB\nC\nD\nE"
        let doc = DocumentModel(content: content)
        let subset = doc.lines(from: 2, to: 4)
        XCTAssertEqual(subset.count, 3)
        XCTAssertEqual(subset[0].content, "B")
        XCTAssertEqual(subset[1].content, "C")
        XCTAssertEqual(subset[2].content, "D")
    }

    func testSearchMatches() {
        let content = """
        Hello World
        Hello Swift
        Goodbye World
        """
        let doc = DocumentModel(content: content)
        let matches = doc.search(for: "Hello")
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].lineNumber, 1)
        XCTAssertEqual(matches[1].lineNumber, 2)
    }

    func testSearchCaseInsensitive() {
        let doc = DocumentModel(content: "Hello HELLO hello")
        let matches = doc.search(for: "hello")
        XCTAssertEqual(matches.count, 3)
    }

    func testSearchCaseSensitive() {
        let doc = DocumentModel(content: "Hello HELLO hello")
        let matches = doc.search(for: "hello", caseSensitive: true)
        XCTAssertEqual(matches.count, 1)
    }
}

final class MarkdownASTTests: XCTestCase {

    func testParseHeadings() {
        let markdown = """
        # Heading 1
        Some text
        ## Heading 2
        More text
        ### Heading 3
        """
        let ast = MarkdownAST(parsing: markdown)
        XCTAssertEqual(ast.headings.count, 3)
        XCTAssertEqual(ast.headings[0].level, 1)
        XCTAssertEqual(ast.headings[0].text, "Heading 1")
        XCTAssertEqual(ast.headings[1].level, 2)
        XCTAssertEqual(ast.headings[2].level, 3)
    }

    func testParseCodeBlocks() {
        let markdown = """
        # Code Example

        ```swift
        let x = 42
        ```

        ```python
        x = 42
        ```
        """
        let ast = MarkdownAST(parsing: markdown)
        XCTAssertEqual(ast.codeBlocks.count, 2)
        XCTAssertEqual(ast.codeBlocks[0].language, "swift")
        XCTAssertTrue(ast.codeBlocks[0].code.contains("let x = 42"))
        XCTAssertEqual(ast.codeBlocks[1].language, "python")
    }

    func testParseLinks() {
        let markdown = """
        Check out [Apple](https://apple.com) and [Google](https://google.com).
        """
        let ast = MarkdownAST(parsing: markdown)
        XCTAssertEqual(ast.links.count, 2)
        XCTAssertEqual(ast.links[0].text, "Apple")
        XCTAssertEqual(ast.links[0].destination, "https://apple.com")
        XCTAssertEqual(ast.links[1].text, "Google")
    }

    func testParseParagraphs() {
        let markdown = """
        First paragraph here.

        Second paragraph here.
        """
        let ast = MarkdownAST(parsing: markdown)
        XCTAssertEqual(ast.paragraphs.count, 2)
        XCTAssertEqual(ast.paragraphs[0].text, "First paragraph here.")
        XCTAssertEqual(ast.paragraphs[1].text, "Second paragraph here.")
    }
}

final class LineTests: XCTestCase {

    func testLineProperties() {
        let content = "Hello"
        let line = Line(
            number: 1,
            range: content.startIndex..<content.endIndex,
            content: content[...]
        )
        XCTAssertEqual(line.number, 1)
        XCTAssertEqual(line.content, "Hello")
        XCTAssertEqual(line.length, 5)
        XCTAssertFalse(line.isEmpty)
    }

    func testEmptyLineDetection() {
        let content = "   "
        let line = Line(
            number: 1,
            range: content.startIndex..<content.endIndex,
            content: content[...]
        )
        XCTAssertTrue(line.isEmpty)
    }
}
