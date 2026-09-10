import Coinage
import SubstrateSdk
import CoreData
import Foundation
import KeyDerivation
import Testing

@testable import polkadot_app

/// Guards the serialization of `CoinageTxCoreDataRepository`'s transaction.
///
/// It once built a new `NSManagedObjectContext` per call instead of using the shared serial one,
/// so two concurrent registrations each read the store before either saved, neither saw the other,
/// both passed the Unique consumer invariant, and both committed — double-spending an input and
/// assigning duplicate `sequence` values.
///
/// Also pins the other half of Unique consumer: a `failure` entry must not keep holding its
/// inputs, or retry after failure would be impossible.
@Suite("CoinageTx registration concurrency")
final class DurabilityRegistrationConcurrencyTests {
    private var facade: UserDataStorageTestFacade!
    private var store: CoinageTxCoreDataRepository!

    init() {
        facade = UserDataStorageTestFacade()
        store = CoinageTxCoreDataRepository(storageFacade: facade)
    }

    @Test("concurrent registrations on the same input admit exactly one")
    func concurrentRegistrationsOnSameInputAdmitExactlyOne() async throws {
        for _ in 0 ..< 50 {
            let facade = UserDataStorageTestFacade()
            let store = CoinageTxCoreDataRepository(storageFacade: facade)
            try await persistCoins([0, 1, 2], facade: facade)

            let sharedInput = CoinageTxInput.coin(.own(0, testKey(0)))
            let id1 = CoinageTxId()
            let id2 = CoinageTxId()

            let entry1 = CoinageTxEntry(
                id: id1,
                inputs: [sharedInput],
                outputs: [.coin(1, testKey(1))],
                txHash: Data(repeating: 0xAB, count: 32),
                checkpoint: BlockRef(number: 100, hash: Data([100])),
                mortality: 64,
                successDetectedAt: nil
            )

            let entry2 = CoinageTxEntry(
                id: id2,
                inputs: [sharedInput],
                outputs: [.coin(2, testKey(2))],
                txHash: Data(repeating: 0xAB, count: 32),
                checkpoint: BlockRef(number: 100, hash: Data([100])),
                mortality: 64,
                successDetectedAt: nil
            )

            var firstError: Error?
            var secondError: Error?
            var firstSucceeded = false
            var secondSucceeded = false

            async let task1: () = Task {
                do {
                    try await store.register(entry1)
                    firstSucceeded = true
                } catch {
                    firstError = error
                }
            }.value

            async let task2: () = Task {
                do {
                    try await store.register(entry2)
                    secondSucceeded = true
                } catch {
                    secondError = error
                }
            }.value

            _ = await (task1, task2)

            // Exactly one should succeed
            let successCount = (firstSucceeded ? 1 : 0) + (secondSucceeded ? 1 : 0)
            #expect(successCount == 1)

            // The rejected one should throw inputAlreadyClaimed
            if firstSucceeded {
                #expect((secondError as? CoinageTxError) == .inputAlreadyClaimed(sharedInput.publicKey.toHex()))
            } else {
                #expect((firstError as? CoinageTxError) == .inputAlreadyClaimed(sharedInput.publicKey.toHex()))
            }
        }
    }

    @Test("concurrent registrations keep sequence monotonic")
    func concurrentRegistrationsKeepSequenceMonotonic() async throws {
        for _ in 0 ..< 50 {
            let facade = UserDataStorageTestFacade()
            let store = CoinageTxCoreDataRepository(storageFacade: facade)
            try await persistCoins((0 ..< 10).map(UInt64.init) + (100 ..< 110).map(UInt64.init), facade: facade)

            let entries = (0 ..< 10).map { i -> CoinageTxEntry in
                let inputIndex = UInt64(i)
                let outputIndex = UInt64(100 + i)
                return CoinageTxEntry(
                    id: CoinageTxId(),
                    inputs: [.coin(.own(inputIndex, testKey(inputIndex)))],
                    outputs: [.coin(outputIndex, testKey(outputIndex))],
                    txHash: Data(repeating: 0xAB, count: 32),
                    checkpoint: BlockRef(number: 100, hash: Data([100])),
                    mortality: 64,
                    successDetectedAt: nil
                )
            }

            var registrationErrors: [Error] = []

            await withTaskGroup(of: Void.self) { group in
                for entry in entries {
                    group.addTask {
                        do {
                            try await store.register(entry)
                        } catch {
                            registrationErrors.append(error)
                        }
                    }
                }
                await group.waitForAll()
            }

            // All registrations should succeed
            #expect(registrationErrors.isEmpty)

            // Fetch all entries and check sequences
            let fetched = try await store.getAllEntries()
            #expect(fetched.count == 10)

            let sequences = fetched.map(\.sequence)
            let uniqueSequences = Set(sequences)

            #expect(uniqueSequences.count == 10)

            // Sequences should be contiguous starting from 1
            let sortedSequences = sequences.sorted()
            let expectedSequences = (1 ... 10).map { Int64($0) }
            #expect(sortedSequences == expectedSequences)
        }
    }

    @Test("rejected registration leaves nothing behind")
    func rejectedRegistrationLeavesNothingBehind() async throws {
        try await persistCoins([0, 1, 2], facade: facade)

        // First registration should succeed
        let firstInput = CoinageTxInput.coin(.own(0, testKey(0)))
        let firstEntry = CoinageTxEntry(
            id: CoinageTxId(),
            inputs: [firstInput],
            outputs: [.coin(1, testKey(1))],
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64,
            successDetectedAt: nil
        )

        try await store.register(firstEntry)

        // Verify we have exactly one entry
        var entries = try await store.getAllEntries()
        #expect(entries.count == 1)

        // Second registration attempts to use the same input — should be rejected
        let secondEntry = CoinageTxEntry(
            id: CoinageTxId(),
            inputs: [firstInput],
            outputs: [.coin(2, testKey(2))],
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64,
            successDetectedAt: nil
        )

        var rejectionError: Error?
        do {
            try await store.register(secondEntry)
        } catch {
            rejectionError = error
        }

        // Verify rejection happened
        #expect((rejectionError as? CoinageTxError) == .inputAlreadyClaimed(firstInput.publicKey.toHex()))

        // Verify store still holds only the first entry and no marks
        entries = try await store.getAllEntries()
        #expect(entries.count == 1)

        // Verify no handoff marks were left behind
        let marks = try await store.handedOffCoins()
        #expect(marks.isEmpty)
    }

    /// Unique consumer excludes `failure` entries, so an input released by a failed entry can be
    /// spent again. This pins the relationship traversal in `claimedInputIdentifiers`: if the
    /// predicate did not reach through to the owning entry's status, every retry after a failure
    /// would be rejected as a double-spend.
    @Test("an input claimed only by a failed entry can be registered again")
    func inputOfFailedEntryIsRegistrableAgain() async throws {
        try await persistCoins([7, 1, 2], facade: facade)

        let input = CoinageTxInput.coin(.own(7, testKey(7)))

        let failedEntry = CoinageTxEntry(
            inputs: [input],
            outputs: [.coin(1, testKey(1))],
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64
        )

        let failedId = try await store.register(failedEntry)
        try await store.updateStatus(failedId, to: .failure)

        // The retry reuses the input but mints a different output — a fresh output is a separate
        // invariant and would mask the one under test.
        let retry = CoinageTxEntry(
            id: CoinageTxId(),
            inputs: [input],
            outputs: [.coin(2, testKey(2))],
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 200, hash: Data([200])),
            mortality: 64
        )

        try await store.register(retry)

        let entries = try await store.getAllEntries()
        #expect(entries.count == 2)
        #expect(entries.filter { $0.status == .failure }.count == 1)
    }

    @Test("an input claimed by a live entry is still rejected after another entry fails")
    func liveClaimSurvivesUnrelatedFailure() async throws {
        try await persistCoins([7, 8, 1, 2, 3], facade: facade)

        let liveInput = CoinageTxInput.coin(.own(7, testKey(7)))

        let failedEntry = CoinageTxEntry(
            inputs: [.coin(.own(8, testKey(8)))],
            outputs: [.coin(1, testKey(1))],
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64
        )
        let liveEntry = CoinageTxEntry(
            inputs: [liveInput],
            outputs: [.coin(2, testKey(2))],
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortality: 64
        )

        let failedId = try await store.register(failedEntry)
        try await store.register(liveEntry)
        try await store.updateStatus(failedId, to: .failure)

        let conflicting = CoinageTxEntry(
            id: CoinageTxId(),
            inputs: [liveInput],
            outputs: [.coin(3, testKey(3))],
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 200, hash: Data([200])),
            mortality: 64
        )

        await #expect(throws: CoinageTxError.inputAlreadyClaimed(liveInput.publicKey.toHex())) {
            try await store.register(conflicting)
        }
    }

    /// Coins must exist before a transaction registers against them, so persist the input and
    /// output coins a test references before it registers any entry.
    private func persistCoins(_ indices: [DerivationIndex], facade: UserDataStorageTestFacade) async throws {
        let repo = facade.makeRepo(mapper: CoinMapper())
        let coins = indices.map { Coin(exponent: 0, derivationIndex: $0, age: nil, publicKey: testKey($0)) }
        try await repo.saveOperation({ coins }, { [] }).asyncExecute()
    }
}

/// A deterministic public key from a derivation index — distinct per index and stable, so the
/// persisted coins' keys match the entries the tests register against them.
private func testKey(_ index: DerivationIndex) -> PublicKey {
    withUnsafeBytes(of: index.bigEndian) { Data($0) }
}

/// The real validator — it reads each entry's own public keys, which `persistCoins` stores to
/// match (both derive the key the same way from the index).
private let concurrencyValidator = CoinageTxRegistrationValidator()

private final class CapturedId: @unchecked Sendable {
    var id: CoinageTxId?
}

private extension CoinageTxCoreDataRepository {
    /// Registers a prepared entry, running the real validator's invariant checks inside the store
    /// transaction, and returns the id the store minted. Keeps the existing `store.register(entry)`
    /// call shape while adapting to the repo-generated-id registration API.
    @discardableResult
    func register(_ entry: CoinageTxEntry) async throws -> CoinageTxId {
        let registration = CoinageTxRegistration(
            txHash: entry.txHash,
            checkpoint: entry.checkpoint,
            mortalityBlocks: entry.mortality,
            groupId: entry.groupId,
            inputs: entry.inputs,
            outputs: entry.outputs
        )
        let captured = CapturedId()
        try await register(
            [registration],
            validation: { try concurrencyValidator.validate([registration], transaction: $0) },
            onCommit: { captured.id = $0.first }
        )
        guard let id = captured.id else { throw CoinageTxError.entryNotFound(entry.id) }
        return id
    }

    /// Test-only convenience mirroring the removed `updateStatus(_:to:)`: reads the current status
    /// and applies a terminal/live verdict through the production compare-and-set.
    func updateStatus(_ id: CoinageTxId, to status: CoinageTxStatus) async throws {
        guard let current = try await getStatus(id) else {
            throw CoinageTxError.entryNotFound(id)
        }
        _ = try await updateTxStatus(
            for: id,
            expectedCurrentStatus: current,
            verdict: Verdict(status: status, successDetectedAt: nil)
        )
    }
}
