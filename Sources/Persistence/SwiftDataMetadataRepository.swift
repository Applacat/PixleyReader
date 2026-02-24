import Foundation
import os.log
import SwiftData

// MARK: - Persistence Logger

private let persistenceLog = Logger(
    subsystem: "com.aimd.reader",
    category: "Persistence"
)

// MARK: - SwiftData Metadata Repository

/// SwiftData implementation of FileMetadataRepository.
///
/// Uses ModelContext for all persistence operations.
/// Thread-safe via @MainActor isolation.
@MainActor
public final class SwiftDataMetadataRepository: FileMetadataRepository {

    // MARK: - Properties

    private let modelContext: ModelContext

    // MARK: - Initialization

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Metadata Operations

    public func getMetadata(for url: URL) -> FileMetadata? {
        let path = url.path
        let descriptor = FetchDescriptor<FileMetadata>(
            predicate: #Predicate { $0.filePath == path }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            return results.first
        } catch {
            return nil
        }
    }

    public func getOrCreateMetadata(for url: URL) -> FileMetadata {
        if let existing = getMetadata(for: url) {
            return existing
        }

        let metadata = FileMetadata(url: url)
        modelContext.insert(metadata)
        saveContext()
        return metadata
    }

    public func saveScrollPosition(_ position: Double, for url: URL) {
        let metadata = getOrCreateMetadata(for: url)
        metadata.scrollPosition = position
        saveContext()
    }

    public func updateLastOpened(for url: URL) {
        let metadata = getOrCreateMetadata(for: url)
        metadata.lastOpened = .now
        saveContext()
    }

    // MARK: - Favorites Operations

    public func setFavorite(_ isFavorite: Bool, for url: URL) {
        let metadata = getOrCreateMetadata(for: url)
        metadata.isFavorite = isFavorite
        saveContext()
    }

    public func getFavorites() -> [URL] {
        let descriptor = FetchDescriptor<FileMetadata>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.lastOpened, order: .reverse)]
        )

        do {
            let results = try modelContext.fetch(descriptor)
            return results.map { $0.url }
        } catch {
            return []
        }
    }

    public func isFavorite(_ url: URL) -> Bool {
        getMetadata(for: url)?.isFavorite ?? false
    }

    // MARK: - Bookmark Operations

    public func getBookmarks(for url: URL) -> [Bookmark] {
        let path = url.path
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.filePath == path },
            sortBy: [SortDescriptor(\.lineNumber)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    @discardableResult
    public func addBookmark(for url: URL, lineNumber: Int, note: String?) -> Bookmark {
        let bookmark = Bookmark(url: url, lineNumber: lineNumber, note: note)
        modelContext.insert(bookmark)
        saveContext()
        return bookmark
    }

    public func deleteBookmark(_ id: UUID) {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            for bookmark in results {
                modelContext.delete(bookmark)
            }
            saveContext()
        } catch {
            // Silently fail - bookmark may already be deleted
        }
    }

    public func deleteAllBookmarks(for url: URL) {
        let bookmarks = getBookmarks(for: url)
        for bookmark in bookmarks {
            modelContext.delete(bookmark)
        }
        saveContext()
    }

    // MARK: - Private Helpers

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            persistenceLog.error("Failed to save context: \(error.localizedDescription)")
        }
    }
}

// MARK: - Schema Versioning

/// Initial schema version (v1.0.0).
/// All future schema changes must add a new VersionedSchema and migration stage.
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [FileMetadata.self, Bookmark.self]
    }
}

/// Migration plan for file metadata persistence.
/// Add new VersionedSchema types and migration stages as the schema evolves.
public enum MetadataMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        // No migrations yet - this is the initial schema.
        // Future migrations go here, e.g.:
        // .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        []
    }
}

// MARK: - Model Container Configuration

/// Configuration helper for creating the SwiftData ModelContainer.
public enum MetadataContainerConfiguration {

    /// Creates a ModelContainer using the versioned migration plan.
    /// - Parameter inMemory: If true, uses in-memory storage (for testing)
    /// - Returns: Configured ModelContainer
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // macOS uses FileVault for full-disk encryption rather than per-file NSFileProtection.
        // Data stored in Application Support is protected by the user's login keychain.
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: MetadataMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
