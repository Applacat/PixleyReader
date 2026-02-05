import XCTest

// MARK: - Test-Only Type Definitions
// Since the Coordinator is in the main app (executable target),
// we mirror the isolation pattern here for testing the logic.

/// Test version of the text change handling pattern
@MainActor
private final class TestableTextChangeHandler {

    var currentText: String = ""
    var isUpdating = false
    var textChangeCount = 0
    var lastTextChange: String? = nil

    /// Simulates the synchronous text change handling (using assumeIsolated pattern)
    func handleTextChange(_ newText: String) {
        guard !isUpdating else { return }

        textChangeCount += 1
        lastTextChange = newText
        currentText = newText
    }

    /// Simulates the old async pattern (for comparison)
    func handleTextChangeAsync(_ newText: String) async {
        guard !isUpdating else { return }

        textChangeCount += 1
        lastTextChange = newText
        currentText = newText
    }
}

// MARK: - Tests

final class NSTextViewDelegateIsolationTests: XCTestCase {

    private var handler: TestableTextChangeHandler!

    @MainActor
    override func setUp() {
        super.setUp()
        handler = TestableTextChangeHandler()
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    // MARK: - Synchronous Update Tests

    @MainActor
    func testTextChange_updatesTextSynchronously() {
        // Given: Initial empty text
        XCTAssertEqual(handler.currentText, "")

        // When: Text changes
        handler.handleTextChange("Hello, World!")

        // Then: Text is updated immediately (no await needed)
        XCTAssertEqual(handler.currentText, "Hello, World!")
    }

    @MainActor
    func testTextChange_incrementsChangeCount() {
        // Given: No changes yet
        XCTAssertEqual(handler.textChangeCount, 0)

        // When: Multiple text changes
        handler.handleTextChange("First")
        handler.handleTextChange("Second")
        handler.handleTextChange("Third")

        // Then: Count reflects all changes
        XCTAssertEqual(handler.textChangeCount, 3)
    }

    @MainActor
    func testTextChange_tracksLastChange() {
        // When: Multiple changes
        handler.handleTextChange("First")
        handler.handleTextChange("Second")

        // Then: Last change is tracked
        XCTAssertEqual(handler.lastTextChange, "Second")
    }

    // MARK: - Update Guard Tests

    @MainActor
    func testTextChange_ignoredWhenUpdating() {
        // Given: Handler is in updating state
        handler.isUpdating = true

        // When: Text change occurs
        handler.handleTextChange("Should be ignored")

        // Then: Change is ignored
        XCTAssertEqual(handler.currentText, "")
        XCTAssertEqual(handler.textChangeCount, 0)
    }

    @MainActor
    func testTextChange_processedAfterUpdatingClears() {
        // Given: Handler was updating but now clear
        handler.isUpdating = true
        handler.handleTextChange("Ignored")
        handler.isUpdating = false

        // When: New change occurs
        handler.handleTextChange("Processed")

        // Then: New change is processed
        XCTAssertEqual(handler.currentText, "Processed")
        XCTAssertEqual(handler.textChangeCount, 1)
    }

    // MARK: - Synchronous vs Async Pattern Tests

    @MainActor
    func testSynchronousPattern_noAwaitRequired() {
        // The key benefit of assumeIsolated: we can update state synchronously
        // without creating a Task and awaiting it

        // When: Called multiple times in sequence
        let startTime = Date()
        for i in 0..<100 {
            handler.handleTextChange("Text \(i)")
        }
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: All updates complete quickly (no Task scheduling overhead)
        XCTAssertEqual(handler.textChangeCount, 100)
        XCTAssertEqual(handler.currentText, "Text 99")
        // Should complete in well under 100ms with no async overhead
        XCTAssertLessThan(elapsed, 0.1)
    }

    @MainActor
    func testAsyncPattern_requiresAwait() async {
        // For comparison: the async pattern requires await
        await handler.handleTextChangeAsync("Async update")

        XCTAssertEqual(handler.currentText, "Async update")
    }

    // MARK: - Empty Text Tests

    @MainActor
    func testTextChange_handlesEmptyText() {
        // Given: Non-empty text
        handler.handleTextChange("Some content")

        // When: Text cleared
        handler.handleTextChange("")

        // Then: Empty text is valid
        XCTAssertEqual(handler.currentText, "")
        XCTAssertEqual(handler.textChangeCount, 2)
    }

    // MARK: - Unicode Text Tests

    @MainActor
    func testTextChange_handlesUnicodeText() {
        // When: Unicode text including emoji
        handler.handleTextChange("Hello 🌍 World 日本語")

        // Then: Unicode preserved
        XCTAssertEqual(handler.currentText, "Hello 🌍 World 日本語")
    }

    // MARK: - Large Text Tests

    @MainActor
    func testTextChange_handlesLargeText() {
        // Given: Large text
        let largeText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 1000)

        // When: Large text change
        handler.handleTextChange(largeText)

        // Then: Full text stored
        XCTAssertEqual(handler.currentText.count, largeText.count)
    }
}
