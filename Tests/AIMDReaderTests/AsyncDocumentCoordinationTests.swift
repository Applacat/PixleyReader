import XCTest

// MARK: - Test-Only Type Definitions
// Since AppState is in the main app (executable target),
// we mirror the callback pattern here for testing the logic.

/// Test version of the document loading callback pattern
@MainActor
private final class TestableDocumentLoader {

    var documentContent: String = ""
    var onDocumentLoaded: (@MainActor () -> Void)? = nil

    /// Simulates document load completion
    func simulateDocumentLoad(content: String) {
        documentContent = content
        onDocumentLoaded?()
        onDocumentLoaded = nil
    }

    /// Simulates the ChatView waiting pattern
    func waitForDocument(timeoutSeconds: TimeInterval) async -> Bool {
        // If document already loaded, return immediately
        if !documentContent.isEmpty {
            return true
        }

        return await withCheckedContinuation { continuation in
            // Set up callback for when document loads
            onDocumentLoaded = {
                continuation.resume(returning: true)
            }

            // Timeout
            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                // Only resume if callback hasn't fired yet
                if self.onDocumentLoaded != nil {
                    self.onDocumentLoaded = nil
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - Tests

final class AsyncDocumentCoordinationTests: XCTestCase {

    private var loader: TestableDocumentLoader!

    @MainActor
    override func setUp() {
        super.setUp()
        loader = TestableDocumentLoader()
    }

    override func tearDown() {
        loader = nil
        super.tearDown()
    }

    // MARK: - Callback Fires After Load Tests

    @MainActor
    func testCallback_firesAfterDocumentLoad() async {
        // Given: A callback is set
        var callbackFired = false
        loader.onDocumentLoaded = {
            callbackFired = true
        }

        // When: Document loads
        loader.simulateDocumentLoad(content: "# Test Content")

        // Then: Callback was fired
        XCTAssertTrue(callbackFired)
    }

    @MainActor
    func testCallback_isClearedAfterFiring() async {
        // Given: A callback is set
        loader.onDocumentLoaded = { }

        // When: Document loads
        loader.simulateDocumentLoad(content: "# Test")

        // Then: Callback is nil
        XCTAssertNil(loader.onDocumentLoaded)
    }

    @MainActor
    func testCallback_contentIsSetBeforeCallback() async {
        // Given: A callback that checks content
        var contentDuringCallback = ""
        loader.onDocumentLoaded = {
            contentDuringCallback = self.loader.documentContent
        }

        // When: Document loads
        loader.simulateDocumentLoad(content: "# Expected Content")

        // Then: Content was set before callback fired
        XCTAssertEqual(contentDuringCallback, "# Expected Content")
    }

    // MARK: - Wait Pattern Tests

    @MainActor
    func testWait_returnsImmediatelyWhenContentAlreadyLoaded() async {
        // Given: Document already loaded
        loader.documentContent = "# Already Loaded"

        // When: Wait for document
        let startTime = Date()
        let result = await loader.waitForDocument(timeoutSeconds: 1.0)
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Returns true immediately (within 100ms)
        XCTAssertTrue(result)
        XCTAssertLessThan(elapsed, 0.1)
    }

    @MainActor
    func testWait_returnsWhenCallbackFires() async {
        // Given: Empty document, will load shortly
        Task {
            // Simulate document loading after 100ms
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                self.loader.simulateDocumentLoad(content: "# Loaded Content")
            }
        }

        // When: Wait for document
        let result = await loader.waitForDocument(timeoutSeconds: 5.0)

        // Then: Returns true when callback fires
        XCTAssertTrue(result)
        XCTAssertEqual(loader.documentContent, "# Loaded Content")
    }

    @MainActor
    func testWait_timeoutReturnsWhenDocumentNeverLoads() async {
        // Given: Document will never load (no simulateDocumentLoad call)

        // When: Wait with short timeout
        let startTime = Date()
        let result = await loader.waitForDocument(timeoutSeconds: 0.2)
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Returns false after timeout
        XCTAssertFalse(result)
        XCTAssertGreaterThanOrEqual(elapsed, 0.2)
        XCTAssertLessThan(elapsed, 0.5) // Should not hang
    }

    // MARK: - Nil Callback (No-Op) Tests

    @MainActor
    func testNilCallback_doesNotCrash() async {
        // Given: No callback set
        XCTAssertNil(loader.onDocumentLoaded)

        // When: Document loads anyway
        loader.simulateDocumentLoad(content: "# Test")

        // Then: No crash, content is set
        XCTAssertEqual(loader.documentContent, "# Test")
    }

    @MainActor
    func testNilCallback_afterClearing_doesNotCrash() async {
        // Given: Callback set then cleared
        loader.onDocumentLoaded = { }
        loader.onDocumentLoaded = nil

        // When: Document loads
        loader.simulateDocumentLoad(content: "# Test")

        // Then: No crash
        XCTAssertEqual(loader.documentContent, "# Test")
    }

    // MARK: - Multiple Load Tests

    @MainActor
    func testCallback_onlyFiresOnce() async {
        // Given: Callback that counts calls
        var callCount = 0
        loader.onDocumentLoaded = {
            callCount += 1
        }

        // When: Document loads twice
        loader.simulateDocumentLoad(content: "# First")
        loader.simulateDocumentLoad(content: "# Second")

        // Then: Callback only fired once (cleared after first)
        XCTAssertEqual(callCount, 1)
    }
}
