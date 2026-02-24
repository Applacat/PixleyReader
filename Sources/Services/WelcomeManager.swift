import Foundation

// MARK: - Welcome Manager

/// Manages the Welcome tutorial folder lifecycle.
/// Ensures the bundled Welcome folder exists in Application Support
/// and provides its URL for first-launch and help menu flows.
///
/// Storage location: `~/Library/Application Support/AIMDReader/Welcome/`
/// Rationale: Application Support is the correct macOS location for app-managed
/// supporting data that persists across launches and is included in backups.
/// The folder is copied from the app bundle on first access.
enum WelcomeManager {

    /// Welcome folder in Application Support (persists reliably, backed up)
    static var welcomeFolderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
            .appendingPathComponent("Welcome")
    }

    /// Ensures Welcome folder exists in Application Support, copying from bundle if needed.
    /// Re-copies when the bundle version is newer (e.g. after an app update).
    /// Returns the folder URL if available, nil if bundle resource is missing.
    static func ensureWelcomeFolder() -> URL? {
        guard let targetURL = welcomeFolderURL else { return nil }
        guard let bundleURL = Bundle.main.url(forResource: "Welcome", withExtension: nil) else {
            return nil
        }

        let fm = FileManager.default

        // If cached copy exists, check if bundle is newer
        if fm.fileExists(atPath: targetURL.path) {
            if !bundleIsNewer(bundleURL: bundleURL, cachedURL: targetURL) {
                return targetURL
            }
            // Bundle is newer — replace cached copy
            try? fm.removeItem(at: targetURL)
        }

        do {
            let parentDir = targetURL.deletingLastPathComponent()
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try fm.copyItem(at: bundleURL, to: targetURL)
            return targetURL
        } catch {
            return nil
        }
    }

    /// Returns true if any file in the bundle Welcome folder is newer than the cached copy.
    private static func bundleIsNewer(bundleURL: URL, cachedURL: URL) -> Bool {
        let fm = FileManager.default
        guard let bundleDate = modificationDate(of: bundleURL, fm: fm),
              let cachedDate = modificationDate(of: cachedURL, fm: fm) else {
            return true  // If we can't tell, re-copy to be safe
        }
        return bundleDate > cachedDate
    }

    private static func modificationDate(of url: URL, fm: FileManager) -> Date? {
        try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
