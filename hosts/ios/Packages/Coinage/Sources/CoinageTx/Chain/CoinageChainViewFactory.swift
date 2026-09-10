import Foundation
import Operation_iOS
@preconcurrency import SubstrateSdk
import SubstrateSdkExt
@preconcurrency import ExtrinsicService
import StructuredConcurrency
import SubstrateOperation
import SubstrateStorageQuery
@preconcurrency import SDKLogger
@preconcurrency import AsyncExtensions
import AsyncAlgorithms
import KeyDerivation

/// Pins one ``CoinageChainViewProtocol`` per pass from a single connection, and owns the head
/// subscriptions that drive recovery.
public protocol CoinageChainViewFactoryProtocol: Sendable {
    /// Reads the finalized and best heads once and returns a view pinned to them. Throws when the
    /// best head is below finality — the peer is inconsistent and the pass must not run against it.
    func pin() async throws -> any CoinageChainViewProtocol

    /// Every newly finalized block, so recovery runs a pass exactly when the facts it reads can
    /// have changed. Resilient: it resubscribes across connection drops and dedups within a
    /// subscription. The number is a tick — each pass still pins its own view.
    func finalizedHeads() -> AnyAsyncSequence<BlockNumber>

    /// Every new best block. `pendingSuccess` and payment status are read at the best head, so
    /// those facts move here rather than at finality — several blocks earlier.
    func bestHeads() -> AnyAsyncSequence<BlockNumber>
}

/// Builds a ``CoinageChainView`` wired to a live connection, folding the former `BlockDataReader`
/// (block-events read) into a private collaborator so the chain view exposes only the
/// three-valued read surface.
final class CoinageChainViewFactory: CoinageChainViewFactoryProtocol, @unchecked Sendable {
    private let coinQuery: any CoinOnChainQuerying
    private let voucherQuery: any VoucherOnChainQuerying
    private let blockInfoProvider: any BlockInfoProviding
    private let blockOutcomeReader: BlockOutcomeReader
    private let logger: SDKLoggerProtocol?

    /// Reconnect attempts before a head subscription gives up and pauses until the next `start()`.
    private static let maxSubscribeAttempts = 5

    init(
        coinQuery: any CoinOnChainQuerying,
        voucherQuery: any VoucherOnChainQuerying,
        blockInfoProvider: any BlockInfoProviding,
        blockEvents: BlockEventsDependencies,
        logger: SDKLoggerProtocol?
    ) {
        self.coinQuery = coinQuery
        self.voucherQuery = voucherQuery
        self.blockInfoProvider = blockInfoProvider
        blockOutcomeReader = BlockOutcomeReader(
            connection: blockEvents.connection,
            runtimeService: blockEvents.runtimeService,
            eventsQueryFactory: BlockEventsQueryFactory(
                operationQueue: blockEvents.operationQueue,
                eventsRepository: SubstrateEventsRepository(),
                storageRequestFactory: blockEvents.storageRequestFactory,
                logger: logger
            )
        )
        self.logger = logger
    }

    /// The connection-bound inputs the factory needs to read block events, grouped so the
    /// initializer stays within the parameter budget.
    struct BlockEventsDependencies {
        let connection: any JSONRPCEngine
        let runtimeService: any RuntimeCodingServiceProtocol
        let operationQueue: OperationQueue
        let storageRequestFactory: any StorageRequestFactoryProtocol
    }
}

// MARK: - Pinning

extension CoinageChainViewFactory {
    func pin() async throws -> any CoinageChainViewProtocol {
        let finalizedNumber = try await blockInfoProvider.fetchFinalized()
        let finalizedHash = try await blockInfoProvider.fetchBlockHash(finalizedNumber)
        let bestNumber = try await blockInfoProvider.fetchCurrent()
        let bestHash = try await blockInfoProvider.fetchBlockHash(bestNumber)

        guard bestNumber >= finalizedNumber else {
            throw CoinageTxError.chainViewUnavailable
        }

        return CoinageChainView(
            checkpoints: ChainView(
                finalized: BlockRef(number: finalizedNumber, hash: finalizedHash),
                best: BlockRef(number: bestNumber, hash: bestHash)
            ),
            coinQuery: coinQuery,
            voucherQuery: voucherQuery,
            blockInfoProvider: blockInfoProvider,
            blockNumberByHash: { [blockOutcomeReader] in await blockOutcomeReader.blockNumber(byHash: $0) },
            blockOutcome: { [blockOutcomeReader] in await blockOutcomeReader.lookUp($0, at: $1) }
        )
    }
}

// MARK: - Head subscriptions

extension CoinageChainViewFactory {
    func finalizedHeads() -> AnyAsyncSequence<BlockNumber> {
        headStream { [blockInfoProvider] in blockInfoProvider.subscribeFinalizedHeads() }
    }

    func bestHeads() -> AnyAsyncSequence<BlockNumber> {
        headStream { [blockInfoProvider] in blockInfoProvider.subscribeNewHeads() }
    }

    /// Wraps `subscribe` in a resilient loop that resubscribes across drops and dedups heads
    /// within one subscription, yielding each head's number as a tick. Relocated from the former
    /// `FinalizedHeadTrigger`.
    private func headStream(
        subscribe: @escaping @Sendable () -> AnyAsyncSequence<Block.Header>
    ) -> AnyAsyncSequence<BlockNumber> {
        AsyncStream<BlockNumber> { continuation in
            let task = Task { [logger] in
                while !Task.isCancelled {
                    do {
                        let heads = try await withRetry(
                            maxAttempts: Self.maxSubscribeAttempts,
                            initialDelay: .seconds(1)
                        ) {
                            let sequence = subscribe()
                            var iterator = sequence.makeAsyncIterator()
                            guard let first = try await iterator.next() else {
                                throw HeadSubscriptionError.subscriptionEndedBeforeFirstHead
                            }
                            return PrefixedHeadSequence(firstElement: first, iterator: iterator)
                                .removeDuplicates { $0.number == $1.number }
                                .eraseToAnyAsyncSequence()
                        }

                        for try await head in heads {
                            guard !Task.isCancelled else { break }
                            if let number = UInt32.fromHex(head.number) {
                                continuation.yield(number)
                            }
                        }
                    } catch RetryError.limitReached {
                        logger?.error("Head subscription exhausted retries, pausing")
                        break
                    } catch {
                        logger?.error("Head subscription failed: \(error), reconnecting")
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyAsyncSequence()
    }
}

private enum HeadSubscriptionError: Error {
    /// The subscription ended before yielding any head.
    case subscriptionEndedBeforeFirstHead
}

// MARK: - Block-events read

/// Looks one extrinsic hash up in one block and resolves its dispatch outcome from that same
/// block's events. Isolates the one access that needs a live connection and runtime metadata.
private final class BlockOutcomeReader: Sendable {
    private let connection: any JSONRPCEngine
    private let runtimeService: any RuntimeCodingServiceProtocol
    private let eventsQueryFactory: any BlockEventsQueryFactoryProtocol

    init(
        connection: any JSONRPCEngine,
        runtimeService: any RuntimeCodingServiceProtocol,
        eventsQueryFactory: any BlockEventsQueryFactoryProtocol
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.eventsQueryFactory = eventsQueryFactory
    }

    func lookUp(_ txHash: Data, at blockHash: Data) async -> BlockLookup {
        guard let blockDetails = try? await queryBlockDetails(blockHash: blockHash) else {
            return .unreadable
        }

        guard let extrinsic = findExtrinsic(txHash: txHash, in: blockDetails) else {
            return .notInBlock
        }

        return await resolveOutcome(extrinsic: extrinsic)
    }

    /// The block's number, read straight from its header via `chain_getHeader`. `nil` when the read
    /// fails or the number cannot be parsed.
    func blockNumber(byHash blockHash: Data) async -> UInt32? {
        let operation = JSONRPCListOperation<Block.Header>(
            engine: connection,
            method: RPCMethod.getBlockHeader,
            parameters: [blockHash.toHex(includePrefix: true)]
        )
        guard let header = try? await operation.asyncExecute() else { return nil }
        return UInt32.fromHex(header.number)
    }
}

private extension BlockOutcomeReader {
    func queryBlockDetails(blockHash: Data) async throws -> SubstrateBlockDetails {
        let wrapper = eventsQueryFactory.queryBlockDetailsWrapper(
            from: connection,
            runtimeProvider: runtimeService,
            blockHash: blockHash
        )
        return try await wrapper.asyncExecute()
    }

    func findExtrinsic(
        txHash: Data,
        in blockDetails: SubstrateBlockDetails
    ) -> SubstrateExtrinsicEvents? {
        blockDetails.extrinsicsWithEvents.first { $0.extrinsicHash == txHash }
    }

    func resolveOutcome(extrinsic: SubstrateExtrinsicEvents) async -> BlockLookup {
        guard let coderFactory = try? await runtimeService.fetchCoderFactoryOperation()
            .asyncExecute() else {
            return .outcome(.failedRead)
        }

        let successMatcher = ExtrinsicSuccessEventMatcher()
        let failureMatcher = ExtrinsicFailureEventMatcher()

        for record in extrinsic.eventRecords {
            if successMatcher.match(event: record.event, using: coderFactory) {
                return .outcome(.present(true))
            }
            if failureMatcher.match(event: record.event, using: coderFactory) {
                return .outcome(.present(false))
            }
        }

        // Applied, but neither outcome event is present — the block was read and still says
        // nothing, so this decides nothing.
        return .outcome(.failedRead)
    }
}

// MARK: - Head subscription wrapper

/// Wraps an iterator to re-yield its first element plus all subsequent elements. Relocated from
/// the former `FinalizedHeadTrigger`.
///
/// Declared `@unchecked Sendable` because `AnyAsyncIterator<Block.Header>` is not `Sendable`
/// (its element type `Block.Header` from SubstrateSdk is not). The iterator is consumed within a
/// single uncontended async task; no concurrent access occurs.
private struct PrefixedHeadSequence: AsyncSequence, @unchecked Sendable {
    typealias Element = Block.Header

    let firstElement: Block.Header
    var iterator: AnyAsyncIterator<Block.Header>

    func makeAsyncIterator() -> Iterator {
        Iterator(firstElement: firstElement, iterator: iterator, yieldedFirst: false)
    }

    struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
        typealias Element = Block.Header

        let firstElement: Block.Header
        var iterator: AnyAsyncIterator<Block.Header>
        var yieldedFirst: Bool

        mutating func next() async throws -> Block.Header? {
            if !yieldedFirst {
                yieldedFirst = true
                return firstElement
            }
            return try await iterator.next()
        }
    }
}
