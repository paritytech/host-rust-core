import CoreData
import Foundation
import Testing
@testable import polkadot_app

/// The store on a device is migrated forward at launch, and a version the
/// bundled models do not cover ends in `UserStorageMigrator`'s `fatalError` —
/// a crash with nothing to do but reinstall.
///
/// The Pocket's version is numbered well clear of the sequence
/// `polkadot-ios-community` is still filling, so it is reached from a long way
/// below. CoreData infers that migration rather than stepping through the
/// versions between, and these prove it gets there.
@Suite("UserStorageMigration")
struct UserStorageMigrationTests {
    /// A store left on the last version before the gap must be recognised as
    /// that version, not as the newest one, or no migration runs and the
    /// Pocket's tables never appear.
    @Test
    func readsTheVersionOfAStoreLeftBeforeTheGap() throws {
        let store = try makeStore(at: .version52)

        #expect(try compatibleVersion(of: store) == .version52)
    }

    /// The whole point of the jump: a store left on the last version before
    /// the gap still reaches the current model, and reaching it is what creates
    /// the Pocket's tables.
    ///
    /// A failure here is a crash rather than a refusal, because that is what
    /// the migrator does with a store it cannot open.
    @Test
    func migratesAStoreFromBeforeTheGapToTheCurrentVersion() throws {
        let store = try makeStore(at: .version52)
        let migrator = UserStorageMigrator(
            storeURL: store,
            modelDirectory: UserStorageParams.modelDirectory,
            model: UserStorageParams.modelVersion,
            fileManager: .default
        )

        #expect(migrator.requiresMigration())
        migrator.performMigration()

        #expect(try compatibleVersion(of: store) == UserStorageParams.modelVersion)
        #expect(!migrator.requiresMigration())
    }

    /// A store already on the current version is left alone, so a launch that
    /// has nothing to do does not rewrite the user's database.
    @Test
    func leavesAStoreAlreadyOnTheCurrentVersionAlone() throws {
        let store = try makeStore(at: UserStorageParams.modelVersion)
        let migrator = UserStorageMigrator(
            storeURL: store,
            modelDirectory: UserStorageParams.modelDirectory,
            model: UserStorageParams.modelVersion,
            fileManager: .default
        )

        #expect(!migrator.requiresMigration())
    }
}

// MARK: - Fixtures

/// A SQLite store created empty at `version`, in a directory of its own so the
/// suite's cases cannot migrate each other's.
private func makeStore(at version: UserStorageVersion) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("user-storage-migration/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let storeURL = directory.appendingPathComponent("UserDataModel.sqlite")
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model(for: version))
    let store = try coordinator.addPersistentStore(
        ofType: NSSQLiteStoreType,
        configurationName: nil,
        at: storeURL,
        options: [NSPersistentHistoryTrackingKey: true]
    )
    try coordinator.remove(store)

    return storeURL
}

private func model(for version: UserStorageVersion) -> NSManagedObjectModel {
    let url = Bundle.main.url(
        forResource: version.rawValue,
        withExtension: "mom",
        subdirectory: UserStorageParams.modelDirectory
    )

    return NSManagedObjectModel(contentsOf: url!)!
}

private func compatibleVersion(of storeURL: URL) throws -> UserStorageVersion? {
    let metadata = try #require(NSPersistentStoreCoordinator.metadata(at: storeURL))

    return UserStorageVersion.allCases.first {
        model(for: $0).isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }
}
