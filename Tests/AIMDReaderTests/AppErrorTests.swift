import XCTest

// MARK: - Test-Only Type Definitions
// Since AppError is in the main app (executable target),
// we mirror the implementation here for testing the logic.
// Note: ErrorBannerTests already tests some of this, but this file
// provides more comprehensive coverage of the AppError type itself.

// MARK: - AppError Mirror

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

    static func fileTooLarge(sizeMB: Double) -> TestableAppError {
        .error(message: String(format: "File too large (%.1f MB). Maximum is 10 MB.", sizeMB))
    }

    static var textSizeExceeded: TestableAppError {
        .warning(message: "Content exceeds size limit. Some features may be disabled.")
    }

    static func fileReadError(_ description: String) -> TestableAppError {
        .error(message: "Unable to read file: \(description)")
    }
}

// MARK: - Tests

final class AppErrorTests: XCTestCase {

    // MARK: - Warning Tests

    func testWarning_isWarningTrue() {
        let error = TestableAppError.warning(message: "Test warning")
        XCTAssertTrue(error.isWarning)
    }

    func testWarning_messagePreserved() {
        let msg = "Something went mildly wrong"
        let error = TestableAppError.warning(message: msg)
        XCTAssertEqual(error.message, msg)
    }

    // MARK: - Error Tests

    func testError_isWarningFalse() {
        let error = TestableAppError.error(message: "Test error")
        XCTAssertFalse(error.isWarning)
    }

    func testError_messagePreserved() {
        let msg = "Something went very wrong"
        let error = TestableAppError.error(message: msg)
        XCTAssertEqual(error.message, msg)
    }

    // MARK: - fileTooLarge Tests

    func testFileTooLarge_formats1DecimalPlace() {
        let error = TestableAppError.fileTooLarge(sizeMB: 15.5)
        XCTAssertTrue(error.message.contains("15.5 MB"))
    }

    func testFileTooLarge_formatsWholeNumber() {
        let error = TestableAppError.fileTooLarge(sizeMB: 20.0)
        XCTAssertTrue(error.message.contains("20.0 MB"))
    }

    func testFileTooLarge_mentionsMaximum() {
        let error = TestableAppError.fileTooLarge(sizeMB: 15.5)
        XCTAssertTrue(error.message.contains("10 MB"))
    }

    func testFileTooLarge_isError() {
        let error = TestableAppError.fileTooLarge(sizeMB: 15.5)
        XCTAssertFalse(error.isWarning)
    }

    // MARK: - textSizeExceeded Tests

    func testTextSizeExceeded_isWarning() {
        let error = TestableAppError.textSizeExceeded
        XCTAssertTrue(error.isWarning)
    }

    func testTextSizeExceeded_hasCorrectMessage() {
        let error = TestableAppError.textSizeExceeded
        XCTAssertTrue(error.message.contains("size limit"))
    }

    // MARK: - fileReadError Tests

    func testFileReadError_includesDescription() {
        let error = TestableAppError.fileReadError("Permission denied")
        XCTAssertTrue(error.message.contains("Permission denied"))
    }

    func testFileReadError_hasPrefix() {
        let error = TestableAppError.fileReadError("Not found")
        XCTAssertTrue(error.message.hasPrefix("Unable to read file:"))
    }

    func testFileReadError_isError() {
        let error = TestableAppError.fileReadError("Something")
        XCTAssertFalse(error.isWarning)
    }

    // MARK: - Equatable Tests

    func testEquatable_sameWarningsAreEqual() {
        let e1 = TestableAppError.warning(message: "test")
        let e2 = TestableAppError.warning(message: "test")
        XCTAssertEqual(e1, e2)
    }

    func testEquatable_sameErrorsAreEqual() {
        let e1 = TestableAppError.error(message: "test")
        let e2 = TestableAppError.error(message: "test")
        XCTAssertEqual(e1, e2)
    }

    func testEquatable_differentMessagesNotEqual() {
        let e1 = TestableAppError.error(message: "test1")
        let e2 = TestableAppError.error(message: "test2")
        XCTAssertNotEqual(e1, e2)
    }

    func testEquatable_warningAndErrorNotEqual() {
        let warning = TestableAppError.warning(message: "test")
        let error = TestableAppError.error(message: "test")
        XCTAssertNotEqual(warning, error)
    }

    func testEquatable_emptyMessages() {
        let e1 = TestableAppError.warning(message: "")
        let e2 = TestableAppError.warning(message: "")
        XCTAssertEqual(e1, e2)
    }
}
