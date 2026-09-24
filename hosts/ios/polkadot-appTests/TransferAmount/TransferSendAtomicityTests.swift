import Coinage
import CoreData
import DurableTransactions
import Foundation
import KeyDerivation
import Operation_iOS
import Testing

@testable import polkadot_app

/// The guard on the transaction-inversion design: a payment's chat message, its handoff commit and its
/// scheduled transactions all become durable in **one** CoreData transaction, or none of them do.
///
/// The ordering matters and nothing else enforces it. A message that persists without its handoff commit
/// would let the coins it just gave away be selected again; a handoff committed without the message
/// would freeze coins for a payment that never left. `performWrite` cannot nest, which is why the
/// message store opens the transaction and hands a scope to the caller rather than the other way round.
@Suite("Transfer send atomicity")
struct TransferSendAtomicityTests {
    private let messageId = "msg-atomic-1"
    private let contact = Data(repeating: 0xC0, count: 32)

    @Test("message, handoff commit and scheduled transaction all land together")
    func everythingCommitsTogether() async throws {
        let world = try await World()
        let handedOff = world.coin(1)
        try await world.precommit([handedOff])

        try await world.messages.save(world.message()) { scope in
            try world.ledger.ledger.commitHandoffs([handedOff.publicKey], in: scope)
            _ = try world.schedule(spending: world.coin(2), minting: world.coin(3), in: scope)
        }

        #expect(try await world.messageExists())
        #expect(try await world.scheduledEntries().count == 1)

        // Committed, not provisional: a relaunch releases uncommitted marks and must leave this one.
        try await world.ledger.ledger.releaseUncommittedHandoffs()
        #expect(try await world.ledger.ledger.getHandoffKeys().contains(handedOff.publicKey))
    }

    @Test("a scheduled transaction is durable with no attempt and holds its inputs")
    func scheduledRowIsDurableWithoutBytes() async throws {
        let world = try await World()
        let spent = world.coin(2)

        try await world.messages.save(world.message()) { scope in
            _ = try world.schedule(spending: spent, minting: world.coin(3), in: scope)
        }

        let entry = try #require(try await world.scheduledEntries().first)
        #expect(entry.entry.status == .pendingSubmission)
        #expect(entry.attempt == nil)
        #expect(entry.inputs == [spent.asInput])
        #expect(entry.groupId == messageId)
    }

    // MARK: - Rollback

    @Test("a throw after scheduling rolls the message back with it")
    func throwAfterSchedulingRollsEverythingBack() async throws {
        let world = try await World()

        await #expect(throws: SendFailure.self) {
            try await world.messages.save(world.message()) { scope in
                _ = try world.schedule(spending: world.coin(2), minting: world.coin(3), in: scope)

                // Whatever carries the keys failed after the rows were written.
                throw SendFailure()
            }
        }

        #expect(try await !world.messageExists())
        #expect(try await world.scheduledEntries().isEmpty)
    }

    @Test("a throw after committing a handoff leaves the coins free")
    func throwAfterHandoffCommitLeavesCoinsFree() async throws {
        let world = try await World()
        let handedOff = world.coin(1)
        try await world.precommit([handedOff])

        await #expect(throws: SendFailure.self) {
            try await world.messages.save(world.message()) { scope in
                try world.ledger.ledger.commitHandoffs([handedOff.publicKey], in: scope)

                throw SendFailure()
            }
        }

        #expect(try await !world.messageExists())

        // The commit rolled back with the message, so the mark is provisional again — and a relaunch
        // drops it, freeing coins that were never actually given away.
        try await world.ledger.ledger.releaseUncommittedHandoffs()
        #expect(try await !world.ledger.ledger.getHandoffKeys().contains(handedOff.publicKey))
    }

    @Test("a hook that throws before writing anything still rolls the message back")
    func throwBeforeWritingRollsMessageBack() async throws {
        let world = try await World()

        await #expect(throws: SendFailure.self) {
            try await world.messages.save(world.message()) { _ in
                throw SendFailure()
            }
        }

        #expect(try await !world.messageExists())
    }

    @Test("a failed send leaves no trace for the next attempt to trip over")
    func aFailedSendCanBeRetried() async throws {
        let world = try await World()

        await #expect(throws: SendFailure.self) {
            try await world.messages.save(world.message()) { scope in
                _ = try world.schedule(spending: world.coin(2), minting: world.coin(3), in: scope)
                throw SendFailure()
            }
        }

        // The same inputs are still free, so the retry registers rather than failing the Unique
        // consumer invariant.
        try await world.messages.save(world.message()) { scope in
            _ = try world.schedule(spending: world.coin(2), minting: world.coin(3), in: scope)
        }

        #expect(try await world.messageExists())
        #expect(try await world.scheduledEntries().count == 1)
    }
}

// MARK: - Support

private struct SendFailure: Error {}

private extension TransferSendAtomicityTests {
    /// The real CoreData stack with both stores over it — the same store the app writes through, since
    /// the thing under test is the transaction, not a model of it.
    struct World {
        let facade: UserDataStorageTestFacade
        let ledger: CoinageCoreDataLedger
        let messages: ChatMessageTransactionalStore
        let messageId = "msg-atomic-1"
        let contact = Data(repeating: 0xC0, count: 32)

        init() async throws {
            facade = UserDataStorageTestFacade()
            ledger = CoinageCoreDataLedger(storageFacade: facade)
            messages = ChatMessageTransactionalStore(storageFacade: facade)

            // The mapper resolves the message's chat and refuses one that does not exist, so the chat
            // is seeded first — a payment is always sent into an existing conversation.
            let chatId = Chat.Id.person(contact).rawRepresentation
            try await facade.databaseService.performWrite { context in
                let chat = try context.insertNew(CDChat.self)
                chat.identifier = chatId
            }

            // The asset ledger joins each input and output to a persisted coin row.
            let repository = facade.makeRepo(mapper: CoinMapper())
            let coins = (1 ... 3).map { item in
                Coin(
                    exponent: 0,
                    derivationIndex: Self.keyIndex(item),
                    age: nil,
                    publicKey: Self.coinKey(item)
                )
            }
            try await repository.saveOperation({ coins }, { [] }).asyncExecute()
        }

        static func keyIndex(_ item: Int) -> CoinageKeyIndex {
            CoinageKeyIndex(installation: .test, item: UInt64(item))
        }

        /// Stable per index, so the persisted coins' keys match the rows the transactions name.
        static func coinKey(_ item: Int) -> PublicKey {
            withUnsafeBytes(of: UInt64(item).bigEndian) { Data($0) }
        }

        func coin(_ item: Int) -> OwnAsset {
            .coin(Self.keyIndex(item), Self.coinKey(item))
        }

        func message() -> Chat.LocalMessage {
            Chat.LocalMessage(
                messageId: messageId,
                chatId: .person(contact),
                origin: .user,
                creationSource: .localDevice,
                status: .outgoing(.new),
                timestamp: 0,
                content: .text("payment"),
                reactions: [],
                compactionId: nil,
                relatedMessages: []
            )
        }

        func precommit(_ assets: [OwnAsset]) async throws {
            try await ledger.ledger.precommitHandOff(assets) { _ in }
        }

        /// Schedules one transaction inside `scope`, the way `PreparedTransfer.commit(in:)` does.
        func schedule(
            spending input: OwnAsset,
            minting output: OwnAsset,
            in scope: any DurableTxRegistrationScope
        ) throws -> [CoinageTxId] {
            let assets = CoinageAssetRegistration(
                inputs: [input.asInput],
                outputs: [output]
            )

            return try ledger.durable.schedule(
                [DurableTxSchedule(
                    domainId: .coinage,
                    groupId: messageId,
                    policy: SubmissionPolicy(id: SubmissionPolicyId("test-policy"), params: Data([1]))
                )],
                joining: scope
            ) { scope, ids in
                try ledger.ledger.registerAssets([assets], for: ids, in: scope)
            }
        }

        func scheduledEntries() async throws -> [CoinageTxEntry] {
            try await ledger.getOperationGroupStatuses(messageId)
        }

        func messageExists() async throws -> Bool {
            let id = messageId

            return try await facade.databaseService.performRead { context in
                let request = NSFetchRequest<CDChatMessage>(entityName: "CDChatMessage")
                request.predicate = NSPredicate(
                    format: "%K == %@",
                    #keyPath(CDChatMessage.messageId),
                    id
                )

                return try context.count(for: request) > 0
            }
        }
    }
}
