import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// Since WelcomeManager is in the main app (executable target),
// we mirror the bundleIsNewer logic here for testing.

// MARK: - bundleIsNewer Mirror

/// Pure logic extracted from WelcomeManager for testing.
/// Compares modification dates to decide if bundle should replace cache.
private func testableBundleIsNewer(bundleDate: Date?, cachedDate: Date?) -> Bool {
    guard let bundleDate, let cachedDate else {
        return true  // If we can't tell, re-copy to be safe
    }
    return bundleDate > cachedDate
}

// MARK: - Tests

final class WelcomeManagerTests: XCTestCase {

    // MARK: - bundleIsNewer Tests

    func testBundleNewer_returnsTrue() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        XCTAssertTrue(testableBundleIsNewer(bundleDate: newer, cachedDate: older))
    }

    func testCacheNewer_returnsFalse() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        XCTAssertFalse(testableBundleIsNewer(bundleDate: older, cachedDate: newer))
    }

    func testEqualDates_returnsFalse() {
        let date = Date(timeIntervalSince1970: 1500)
        XCTAssertFalse(testableBundleIsNewer(bundleDate: date, cachedDate: date))
    }

    func testMissingBundleDate_returnsTrue() {
        let cachedDate = Date()
        XCTAssertTrue(testableBundleIsNewer(bundleDate: nil, cachedDate: cachedDate))
    }

    func testMissingCacheDate_returnsTrue() {
        let bundleDate = Date()
        XCTAssertTrue(testableBundleIsNewer(bundleDate: bundleDate, cachedDate: nil))
    }

    func testBothDatesNil_returnsTrue() {
        XCTAssertTrue(testableBundleIsNewer(bundleDate: nil, cachedDate: nil))
    }

    func testBundleOneSecondNewer_returnsTrue() {
        let baseDate = Date()
        let bundleDate = baseDate.addingTimeInterval(1)
        XCTAssertTrue(testableBundleIsNewer(bundleDate: bundleDate, cachedDate: baseDate))
    }

    func testBundleOneSecondOlder_returnsFalse() {
        let baseDate = Date()
        let bundleDate = baseDate.addingTimeInterval(-1)
        XCTAssertFalse(testableBundleIsNewer(bundleDate: bundleDate, cachedDate: baseDate))
    }
}
