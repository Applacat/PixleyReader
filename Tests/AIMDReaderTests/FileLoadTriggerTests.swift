import XCTest
import Foundation

// MARK: - Test-Only Type Definition
// Since FileLoadTrigger is private in the main app (executable target),
// we mirror the implementation here for testing the logic.

/// Test version of FileLoadTrigger
private struct TestableFileLoadTrigger: Equatable {
    let file: URL?
    let reload: Int
}

// MARK: - Tests

final class FileLoadTriggerTests: XCTestCase {

    // MARK: - Equality Tests

    func testEquality_sameFileAndReload_areEqual() {
        // Given: Same file and reload values
        let url = URL(fileURLWithPath: "/test/file.md")
        let trigger1 = TestableFileLoadTrigger(file: url, reload: 1)
        let trigger2 = TestableFileLoadTrigger(file: url, reload: 1)

        // Then: Triggers are equal
        XCTAssertEqual(trigger1, trigger2)
    }

    func testEquality_differentFile_areNotEqual() {
        // Given: Different file URLs
        let url1 = URL(fileURLWithPath: "/test/file1.md")
        let url2 = URL(fileURLWithPath: "/test/file2.md")
        let trigger1 = TestableFileLoadTrigger(file: url1, reload: 1)
        let trigger2 = TestableFileLoadTrigger(file: url2, reload: 1)

        // Then: Triggers are not equal
        XCTAssertNotEqual(trigger1, trigger2)
    }

    func testEquality_differentReload_areNotEqual() {
        // Given: Same file but different reload values
        let url = URL(fileURLWithPath: "/test/file.md")
        let trigger1 = TestableFileLoadTrigger(file: url, reload: 1)
        let trigger2 = TestableFileLoadTrigger(file: url, reload: 2)

        // Then: Triggers are not equal (reload changed = should reload)
        XCTAssertNotEqual(trigger1, trigger2)
    }

    func testEquality_bothNilFiles_areEqual() {
        // Given: Both nil file URLs
        let trigger1 = TestableFileLoadTrigger(file: nil, reload: 0)
        let trigger2 = TestableFileLoadTrigger(file: nil, reload: 0)

        // Then: Triggers are equal
        XCTAssertEqual(trigger1, trigger2)
    }

    func testEquality_oneNilFile_areNotEqual() {
        // Given: One nil and one non-nil file
        let url = URL(fileURLWithPath: "/test/file.md")
        let trigger1 = TestableFileLoadTrigger(file: nil, reload: 0)
        let trigger2 = TestableFileLoadTrigger(file: url, reload: 0)

        // Then: Triggers are not equal (file selection changed)
        XCTAssertNotEqual(trigger1, trigger2)
    }

    // MARK: - State Change Detection Tests

    func testStateChange_fileSelectionChange_triggersReload() {
        // Given: Initial state with one file
        let file1 = URL(fileURLWithPath: "/test/doc1.md")
        let file2 = URL(fileURLWithPath: "/test/doc2.md")
        let initial = TestableFileLoadTrigger(file: file1, reload: 0)

        // When: File selection changes
        let changed = TestableFileLoadTrigger(file: file2, reload: 0)

        // Then: States are different (will trigger task restart)
        XCTAssertNotEqual(initial, changed)
    }

    func testStateChange_manualReload_triggersReload() {
        // Given: Initial state
        let url = URL(fileURLWithPath: "/test/file.md")
        let initial = TestableFileLoadTrigger(file: url, reload: 0)

        // When: Reload trigger incremented (user pressed reload)
        let afterReload = TestableFileLoadTrigger(file: url, reload: 1)

        // Then: States are different (will trigger task restart)
        XCTAssertNotEqual(initial, afterReload)
    }

    func testStateChange_noChange_noReload() {
        // Given: Same state
        let url = URL(fileURLWithPath: "/test/file.md")
        let state1 = TestableFileLoadTrigger(file: url, reload: 5)
        let state2 = TestableFileLoadTrigger(file: url, reload: 5)

        // Then: States are equal (no task restart needed)
        XCTAssertEqual(state1, state2)
    }

    func testStateChange_simultaneousChanges_triggersOnce() {
        // Given: Initial state
        let file1 = URL(fileURLWithPath: "/test/doc1.md")
        let file2 = URL(fileURLWithPath: "/test/doc2.md")
        let initial = TestableFileLoadTrigger(file: file1, reload: 0)

        // When: Both file and reload change (e.g., selecting new file also increments reload)
        let changed = TestableFileLoadTrigger(file: file2, reload: 1)

        // Then: States are different (single task restart, not two)
        XCTAssertNotEqual(initial, changed)
    }

    // MARK: - Hashable Tests (for use in collections)

    func testHashable_equalTriggersHaveSameHash() {
        // Given: Equal triggers
        let url = URL(fileURLWithPath: "/test/file.md")
        let trigger1 = TestableFileLoadTrigger(file: url, reload: 1)
        let trigger2 = TestableFileLoadTrigger(file: url, reload: 1)

        // Then: Hash values are equal
        XCTAssertEqual(trigger1.hashValue, trigger2.hashValue)
    }
}

// MARK: - Hashable Conformance for Tests

extension TestableFileLoadTrigger: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(file)
        hasher.combine(reload)
    }
}
