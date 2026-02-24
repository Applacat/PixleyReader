import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// FileWatcher uses DispatchSource which is hard to test directly.
// We mirror the key deduplication logic: only fire onChange when
// modificationDate differs from lastModificationDate.

// MARK: - FileWatcher Mirror

/// Mirrors FileWatcher's deduplication logic without DispatchSource.
/// The key behavior: handleFileEvent only triggers onChange when
/// the modification date has actually changed.
@MainActor
private final class TestableFileWatcher {

    private(set) var lastModificationDate: Date?
    private(set) var isWatching = false
    private(set) var onChangeCallCount = 0

    /// Simulates watch() — records initial modification date
    func watch(initialModificationDate: Date?) {
        stop()
        lastModificationDate = initialModificationDate
        isWatching = true
    }

    /// Simulates stop()
    func stop() {
        isWatching = false
    }

    /// Mirrors handleFileEvent — only fires onChange when date differs
    func handleFileEvent(currentModificationDate: Date?) {
        guard currentModificationDate != lastModificationDate else { return }
        lastModificationDate = currentModificationDate
        onChangeCallCount += 1
    }
}

// MARK: - Tests

final class FileWatcherTests: XCTestCase {

    private var watcher: TestableFileWatcher!

    override func setUp() async throws {
        watcher = await TestableFileWatcher()
    }

    override func tearDown() async throws {
        watcher = nil
    }

    // MARK: - Deduplication Logic

    @MainActor
    func testSameModificationDate_doesNotTriggerOnChange() {
        let date = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: date)

        // Same date — no change
        watcher.handleFileEvent(currentModificationDate: date)
        XCTAssertEqual(watcher.onChangeCallCount, 0)
    }

    @MainActor
    func testDifferentModificationDate_triggersOnChange() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        watcher.watch(initialModificationDate: date1)

        // Different date — triggers change
        watcher.handleFileEvent(currentModificationDate: date2)
        XCTAssertEqual(watcher.onChangeCallCount, 1)
        XCTAssertEqual(watcher.lastModificationDate, date2)
    }

    // MARK: - Watch Lifecycle

    @MainActor
    func testWatch_replacesPreviousWatch() {
        let date1 = Date(timeIntervalSince1970: 1000)
        watcher.watch(initialModificationDate: date1)
        XCTAssertTrue(watcher.isWatching)

        // Watch again — replaces previous
        let date2 = Date(timeIntervalSince1970: 2000)
        watcher.watch(initialModificationDate: date2)
        XCTAssertTrue(watcher.isWatching)
        XCTAssertEqual(watcher.lastModificationDate, date2)
    }

    @MainActor
    func testStop_clearsWatchingState() {
        watcher.watch(initialModificationDate: Date())
        XCTAssertTrue(watcher.isWatching)

        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
    }

    // MARK: - Integration with Real Temp Files

    @MainActor
    func testRealFile_writeTriggersChange() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.md")
        try "initial content".write(to: fileURL, atomically: true, encoding: .utf8)

        let initialDate = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        watcher.watch(initialModificationDate: initialDate)

        // Wait a moment, then write new content
        Thread.sleep(forTimeInterval: 0.05)
        try "updated content".write(to: fileURL, atomically: true, encoding: .utf8)

        let newDate = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        watcher.handleFileEvent(currentModificationDate: newDate)

        XCTAssertEqual(watcher.onChangeCallCount, 1)
    }

    @MainActor
    func testRealFile_noWriteNoChange() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.md")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let date = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        watcher.watch(initialModificationDate: date)

        // Same file, same date — no spurious callback
        watcher.handleFileEvent(currentModificationDate: date)
        XCTAssertEqual(watcher.onChangeCallCount, 0)
    }
}
