import Foundation
import XCTest

// MARK: - Shared Test Helpers

/// Safely convert string to Data for tests - returns empty Data if conversion fails.
/// Used across multiple test files (RecentFoldersManager, SecurityScopedBookmarkManager, etc.)
extension String {
    var testData: Data {
        data(using: .utf8) ?? Data()
    }
}

/// Creates a file URL for testing purposes.
/// - Parameters:
///   - name: File name without extension
///   - ext: File extension (default: "md")
///   - directory: Parent directory path (default: "/tmp/test")
/// - Returns: A file URL suitable for testing
func makeTestURL(_ name: String, extension ext: String = "md", directory: String = "/tmp/test") -> URL {
    URL(fileURLWithPath: directory).appendingPathComponent("\(name).\(ext)")
}

/// Creates a folder URL for testing purposes.
/// - Parameter name: Folder name
/// - Parameter parent: Parent directory path (default: "/tmp/test")
/// - Returns: A directory URL suitable for testing
func makeTestFolderURL(_ name: String, parent: String = "/tmp/test") -> URL {
    URL(fileURLWithPath: parent).appendingPathComponent(name, isDirectory: true)
}
