# Data Persistence

## Overview

Three persistence layers: CoreData (primary), UserDefaults (preferences), and iCloud (sync).

## CoreData

### Two Separate Models

1. **SubstrateDataStorageFacade** — blockchain data (chains, assets, balances, accounts)
   - Model: `SubstrateDataModel.xcdatamodeld`
   - For chain metadata, asset registries, account data

2. **UserDataStorageFacade** — user data (contacts, preferences, identity)
   - Model: `UserDataModel.xcdatamodeld` (31 version migrations!)
   - For user-specific data, chat, settings

### Repository Pattern

```swift
// CoreDataRepository<T, U> with CoreDataCodable protocol
// T = CoreData NSManagedObject subclass
// U = domain model

let repository = CoreDataRepository<CDModel, DomainModel>(
    storageFacade: SubstrateDataStorageFacade.shared,
    mapper: AnyCoreDataMapper(mapper)
)
```

### Mapper Pattern (Critical)

**When modifying part of an existing entity, create a separate mapper instead of fetch-modify-save.**

```swift
// GOOD: Separate mapper for partial updates — prevents race conditions
class PartialEntityMapper: CoreDataMapperProtocol {
    func apply(changes: PartialUpdate, to entity: CDEntity) {
        entity.specificField = changes.value
    }
}

// BAD: Fetch-modify-save — race condition prone
let entity = try fetch(id)
entity.field = newValue
try save(entity)
```

This is documented in CLAUDE.md and enforced in reviews.

### Migration

- `Common/Storage/Migration/` — migration strategies
- UserDataModel has 31 versions — always add a new version for schema changes
- Test migrations thoroughly

#### Adding a UserDataModel version (all four steps, same PR)

Missing any of these compiles fine but breaks migration at runtime (step 4 has been missed more than
once — the schema shipped while the facade still loaded the previous model):

1. Copy the latest `UserDataModel{N}.xcdatamodel` to `UserDataModel{N+1}.xcdatamodel` inside
   `UserDataModel.xcdatamodeld` and apply the schema change there; update `.xccurrentversion`.
2. Add `case version{N+1} = "UserDataModel{N+1}"` to `UserStorageVersion`.
3. Chain it in `UserStorageVersion.nextVersion()` (`version{N} → version{N+1}`, new case → nil).
4. Switch `UserStorageParams.modelVersion` to `.version{N+1}` in `UserDataStorageFacade.swift`.

Lightweight migration (automatic + inferred mapping) covers additive changes; new non-optional
attributes need a `defaultValueString`. If lightweight isn't possible, add an
`NSEntityMigrationPolicy` (see the doc comment on `UserStorageParams`).

## UserDefaults

- **Use `SettingsManager`** instead of direct UserDefaults access
- Located in `Common/UserDefaults/` (5 items)
- For session data and user preferences

## iCloud

- **CloudBackup module** for data synchronization
- `coinageBackupSyncService` in ServiceCoordinator for coinage sync
- Located in `Inherited/CloudBackup/` (legacy) and `Common/Cloud/`

## Lazy Repository Creation

When a service may need different repository types at different times, store the `StorageFacadeProtocol` reference and create repositories on demand:

```swift
// GOOD: Store facade, create repos lazily
class SomeService {
    private let storageFacade: StorageFacadeProtocol

    init(storageFacade: StorageFacadeProtocol) {
        self.storageFacade = storageFacade
    }

    func fetchItems() {
        let repo = storageFacade.createRepository(/* specific config */)
    }
}

// BAD: Eagerly create single repo in init
class SomeService {
    private let repository: CoreDataRepository<CDItem, Item>  // Locked to one type
}
```

(review: "store facade to create different repositories depending on the case")

## Hard Rules

1. **Separate mappers for partial updates** — prevents race conditions
2. **Use `SettingsManager`** — not direct UserDefaults
3. **New CoreData version for schema changes** — never modify existing versions
4. **Repository pattern for all data access** — `CoreDataRepository<T, U>` with typed mappers
5. **Feature-specific entity naming** — prefix entity names with feature context
6. **Store facade for lazy repos** — when multiple repository types needed, store facade and create on demand

## Seams

| Seam                       | Where                                    | When to touch                        |
|----------------------------|------------------------------------------|--------------------------------------|
| Substrate storage facade   | `Common/Storage/SubstrateDataStorageFacade` | Blockchain data schema changes    |
| User storage facade        | `Common/Storage/UserDataStorageFacade`   | User data schema changes             |
| CoreData models            | `*.xcdatamodeld`                         | Entity/attribute changes             |
| Migration strategies       | `Common/Storage/Migration/`              | Schema migration logic               |
| Settings manager           | `Common/UserDefaults/`                   | Adding new preference keys           |
