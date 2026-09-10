import Coinage
import CoreData
import Foundation
import Testing

@testable import polkadot_app

/// The durability group-status seam against the real `CoinageTxCoreDataRepository` over in-memory
/// CoreData: `getOperationGroupStatuses` / `subscribeOperationGroupStatuses` find every transaction
/// registered under `groupId = messageId`, which is how a claim or a payment tracks its group.
@Suite("Durability group-status query")
struct CoinageGroupStatusQueryTests {
    @Test("Fetch returns only the group's entries, in registration (sequence) order")
    func fetchByGroup() async throws {
        let store = makeStore()
        try await register(store, group: "msg-A", key: 1)
        try await register(store, group: "msg-B", key: 2)
        try await register(store, group: "msg-A", key: 3)

        let groupA = try await store.getOperationGroupStatuses("msg-A")
        #expect(groupA.count == 2)
        #expect(groupA.map(\.sequence) == groupA.map(\.sequence).sorted())
        #expect(Set(groupA.compactMap(\.groupId)) == ["msg-A"])

        let unknown = try await store.getOperationGroupStatuses("msg-Z")
        #expect(unknown.isEmpty)
    }

    @Test("Subscription's first emission is the group's current set")
    func subscribeCurrentSet() async throws {
        let store = makeStore()
        try await register(store, group: "g", key: 1)
        try await register(store, group: "g", key: 2)
        try await register(store, group: "other", key: 3)

        var iterator = store.subscribeOperationGroupStatuses("g").makeAsyncIterator()
        let first = try await iterator.next()

        #expect(first?.count == 2)
        #expect(first?.allSatisfy { $0.groupId == "g" } == true)
    }
}

private extension CoinageGroupStatusQueryTests {
    func makeStore() -> CoinageTxCoreDataRepository {
        CoinageTxCoreDataRepository(storageFacade: UserDataStorageTestFacade())
    }

    /// Registers a received-input entry (no local coin needed) under `group`, bypassing invariant
    /// validation — the seam under test is the persistence query, not registration.
    func register(_ store: CoinageTxCoreDataRepository, group: CoinageTxGroupId, key: UInt8) async throws {
        let registration = CoinageTxRegistration(
            txHash: Data(repeating: key, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortalityBlocks: 64,
            groupId: group,
            inputs: [.coin(.received(Data(repeating: key, count: 32)))],
            outputs: []
        )
        try await store.register([registration], validation: { _ in }, onCommit: { _ in })
    }
}
