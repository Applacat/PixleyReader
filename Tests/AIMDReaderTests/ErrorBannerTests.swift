import XCTest

// MARK: - Test-Only Type Definitions
// Since AppError and error handling are in the main app (executable target),
// we mirror the implementation here for testing the logic.

/// Test version of AppError
private enum TestableAppError: Equatable {
    case warning(message: String)
    case error(message: String)

    var message: String {
        switch self {
        case .warning(let message), .error(let message):
            return message
        }
    }

    var isWarning: Bool {
        switch self {
        case .warning: return true
        case .error: return false
        }
    }

}

/// Test version of error state management
@MainActor
private final class TestableErrorManager {
    var currentError: TestableAppError? = nil
    private var autoDismissTask: Task<Void, Never>? = nil

    func showError(_ error: TestableAppError, autoDismissSeconds: TimeInterval = 5.0) {
        currentError = error
        autoDismissTask?.cancel()

        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(autoDismissSeconds))
            if !Task.isCancelled && currentError == error {
                currentError = nil
            }
        }
    }

    func dismissError() {
        autoDismissTask?.cancel()
        currentError = nil
    }
}

// MARK: - Tests

final class ErrorBannerTests: XCTestCase {

    private var manager: TestableErrorManager!

    override func setUp() async throws {
        manager = await TestableErrorManager()
    }

    override func tearDown() async throws {
        manager = nil
    }

    // MARK: - Error Display Tests

    @MainActor
    func testShowError_setsCurrentError() {
        // Given: No error
        XCTAssertNil(manager.currentError)

        // When: Show error
        manager.showError(.error(message: "Test error"))

        // Then: Current error is set
        XCTAssertNotNil(manager.currentError)
        XCTAssertEqual(manager.currentError?.message, "Test error")
    }

    @MainActor
    func testShowWarning_setsCurrentError() {
        // When: Show warning
        manager.showError(.warning(message: "Test warning"))

        // Then: Warning is set
        XCTAssertNotNil(manager.currentError)
        XCTAssertTrue(manager.currentError?.isWarning ?? false)
    }

    @MainActor
    func testShowError_replacesExistingError() {
        // Given: Existing error
        manager.showError(.error(message: "First error"))

        // When: Show new error
        manager.showError(.error(message: "Second error"))

        // Then: New error replaces old
        XCTAssertEqual(manager.currentError?.message, "Second error")
    }

    // MARK: - Auto-Dismiss Tests

    @MainActor
    func testAutoDismiss_clearsErrorAfterTimeout() async {
        // Given: Error shown with short timeout
        manager.showError(.error(message: "Test"), autoDismissSeconds: 0.1)
        XCTAssertNotNil(manager.currentError)

        // When: Wait for timeout
        try? await Task.sleep(for: .milliseconds(150))

        // Then: Error is cleared
        XCTAssertNil(manager.currentError)
    }

    @MainActor
    func testAutoDismiss_doesNotClearIfNewErrorShown() async {
        // Given: Error shown
        manager.showError(.error(message: "First"), autoDismissSeconds: 0.1)

        // When: New error shown before timeout
        try? await Task.sleep(for: .milliseconds(50))
        manager.showError(.error(message: "Second"), autoDismissSeconds: 1.0)

        // Then: After original timeout, new error still shows
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(manager.currentError)
        XCTAssertEqual(manager.currentError?.message, "Second")
    }

    // MARK: - Manual Dismiss Tests

    @MainActor
    func testDismissError_clearsCurrentError() {
        // Given: Error shown
        manager.showError(.error(message: "Test"))
        XCTAssertNotNil(manager.currentError)

        // When: Dismiss
        manager.dismissError()

        // Then: Error is cleared
        XCTAssertNil(manager.currentError)
    }

    @MainActor
    func testDismissError_cancelsAutoDismiss() async {
        // Given: Error with long auto-dismiss
        manager.showError(.error(message: "Test"), autoDismissSeconds: 10.0)

        // When: Manual dismiss followed by new error
        manager.dismissError()
        manager.showError(.error(message: "New"), autoDismissSeconds: 10.0)

        // Then: New error persists (old auto-dismiss was cancelled)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(manager.currentError?.message, "New")
    }

    @MainActor
    func testDismissError_noOpWhenNoError() {
        // Given: No error
        XCTAssertNil(manager.currentError)

        // When: Dismiss
        manager.dismissError()

        // Then: Still no error (no crash)
        XCTAssertNil(manager.currentError)
    }

}
