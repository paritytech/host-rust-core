import AsyncExtensions
import Foundation
import SubstrateSdk
@testable import Coinage

/// Drives a ``FakeChain`` and hands out views over it, standing in for the chain half of the
/// subsystem. Every read honours the ``CoinageChainViewProtocol`` contract: a failure mode becomes
/// `failedRead`, never `absent`.
///
/// `faults` is mutable so a single-pass fault can be switched on, a pass run, then switched off —
/// each pinned view captures the faults in force at pin time.
final class FakeCoinageChainViewFactory: CoinageChainViewFactoryProtocol, @unchecked Sendable {
    let chain: FakeChain
    var faults: ChainReadFaults = .none

    /// How many times a view was pinned, so a scenario can assert a pass did not read the chain.
    private(set) var pins = 0

    init(chain: FakeChain) {
        self.chain = chain
    }

    func pin() async throws -> any CoinageChainViewProtocol {
        pins += 1

        if faults.pinFails {
            throw ChainReadFailure(message: "pin failed")
        }

        let finalized = chain.finalizedHead
        let best = chain.bestHead
        return FakeCoinageChainView(
            chain: chain,
            // Read live, not snapshotted at pin: a fault switched on after a view is pinned (a watcher
            // scenario blinding a block mid-flight) is a read-time transport failure, so it must reach a
            // read this view makes later.
            faults: { [self] in faults },
            finalized: BlockRef(number: finalized.number, hash: finalized.hash),
            best: BlockRef(number: best.number, hash: best.hash)
        )
    }

    func finalizedHeads() -> AnyAsyncSequence<BlockNumber> {
        AsyncStream<BlockNumber> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func bestHeads() -> AnyAsyncSequence<BlockNumber> {
        AsyncStream<BlockNumber> { $0.finish() }.eraseToAnyAsyncSequence()
    }
}

/// One pinned view over the fake chain, bound to the two heads read when it was pinned.
private final class FakeCoinageChainView: CoinageChainViewProtocol, @unchecked Sendable {
    let finalizedHead: BlockRef
    let bestHead: BlockRef

    private let chain: FakeChain
    private let faultsProvider: () -> ChainReadFaults
    private var faults: ChainReadFaults { faultsProvider() }

    init(chain: FakeChain, faults: @escaping () -> ChainReadFaults, finalized: BlockRef, best: BlockRef) {
        self.chain = chain
        faultsProvider = faults
        finalizedHead = finalized
        bestHead = best
    }

    func readInputs(_ inputs: [CoinageTxInput], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        inputs.map { read($0, at: block) }
    }

    func readOutputs(_ outputs: [OwnAsset], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        outputs.map { read($0.asInput, at: block) }
    }

    func blockHash(at number: UInt32) async -> ReadResult<Data> {
        if faults.everyBlockUnreadable || faults.unreadableBlocks.contains(number) {
            return .failedRead
        }
        guard let block = chain.canonicalAt(number) else { return .absent }
        return .present(block.hash)
    }

    func blockRef(forHash hash: Data) async -> ReadResult<BlockRef> {
        guard let block = chain.blockAt(hash: hash) else { return .failedRead }
        if faults.everyBlockUnreadable || faults.unreadableBlocks.contains(block.number) {
            return .failedRead
        }
        return .present(BlockRef(number: block.number, hash: block.hash))
    }

    func dispatchOutcome(txHash: Data, at block: BlockRef) async -> ReadResult<Bool> {
        switch lookUp(txHash, atBlockHash: block.hash) {
        case let .outcome(result): result
        case .notInBlock,
             .unreadable: .failedRead
        }
    }

    /// Newest block first, mirroring the production ``BlockBodyScan``: a hit reads the dispatch
    /// outcome from the same block; a window not read in full decides nothing.
    func searchBodies(for txHash: Data, in window: ClosedRange<UInt32>) async -> BodySearchOutcome {
        if faults.txSearchDisabled { return .incomplete }

        var everyBlockRead = true
        for number in window.reversed() {
            guard let candidate = chain.canonicalAt(number),
                  !faults.everyBlockUnreadable,
                  !faults.unreadableBlocks.contains(number)
            else {
                everyBlockRead = false
                continue
            }

            let ref = BlockRef(number: number, hash: candidate.hash)
            switch lookUp(txHash, atBlockHash: candidate.hash) {
            case .unreadable:
                everyBlockRead = false
            case .notInBlock:
                continue
            case let .outcome(result):
                return mapSearchOutcome(result: result, block: ref)
            }
        }

        return everyBlockRead ? .notFoundWindowComplete : .incomplete
    }
}

// MARK: - One-asset resolution

private extension FakeCoinageChainView {
    func read(_ input: CoinageTxInput, at block: BlockRef) -> ReadResult<AssetPresence> {
        guard let state = chain.stateAt(hash: block.hash) else { return .failedRead }

        if input.isCoin {
            return readCoin(input.publicKey, in: state, at: block)
        }
        guard case let .recyclerVoucher(index, memberKey) = input else { return .failedRead }
        return readVoucher(index: index, memberKey: memberKey, in: state)
    }

    func readCoin(_ key: PublicKey, in state: CoinageChainState, at block: BlockRef) -> ReadResult<AssetPresence> {
        if faults.unreadableCoins.contains(key) || faults.statelessBlocks.contains(block.hash) {
            return .failedRead
        }
        return state.coins[key] != nil ? .present(AssetPresence()) : .absent
    }

    /// Mirrors ``VoucherOnChainQueryService``: a recycler member is present whatever its ring position —
    /// Onboarding and Suspended included. A non-member (archival) reads `failedRead` (unknown), never
    /// absent, since a voucher's disappearance from the recycler is not consumption. `isUnloaded` is set
    /// only for a ring-placed voucher whose alias reads set; without a ring index there is no alias, so
    /// it reads not-unloaded.
    func readVoucher(
        index: DerivationIndex,
        memberKey: PublicKey,
        in state: CoinageChainState
    ) -> ReadResult<AssetPresence> {
        if faults.membershipsUnreadable { return .failedRead }
        guard let exponent = state.recyclerMembers[memberKey] else { return .failedRead }

        if faults.ringPositionsUnreadable { return .failedRead }
        guard let position = state.ringPositions[memberKey] else { return .failedRead }

        switch position {
        case .onboarding:
            // Never in a ring, so no unload was possible: provably not-unloaded without a read.
            return .present(AssetPresence(alias: .notUnloaded))
        case .suspended:
            // Once in a ring, none now: the alias key cannot be formed, so nothing can be said.
            return .present(AssetPresence(alias: .unknown))
        case let .included(ringIndex):
            let aliasKey = CoinageChainState.aliasKey(index: index, exponent: exponent, ringIndex: ringIndex)
            if faults.unreadableAliases.contains(aliasKey) {
                // A failed alias read leaves the voucher present but its unload state unknown.
                return .present(AssetPresence(alias: .unknown))
            }
            let unloaded = state.aliases[aliasKey] == true
            return .present(AssetPresence(alias: unloaded ? .unloaded : .notUnloaded))
        }
    }
}

// MARK: - Block-body lookup

private extension FakeCoinageChainView {
    func lookUp(_ txHash: Data, atBlockHash blockHash: Data) -> BlockLookup {
        guard let block = chain.blockAt(hash: blockHash) else { return .unreadable }
        if faults.unreadableOutcomes.contains(txHash) { return .unreadable }
        if faults.everyBlockUnreadable || faults.unreadableBlocks.contains(block.number) {
            return .unreadable
        }
        guard block.body.contains(txHash) else { return .notInBlock }

        guard let success = block.state.outcomes[txHash] else { return .outcome(.failedRead) }
        return .outcome(.present(success))
    }

    func mapSearchOutcome(result: ReadResult<Bool>, block: BlockRef) -> BodySearchOutcome {
        switch result {
        case .present(true): .foundSucceeded(block)
        case .present(false): .foundFailed(block)
        case .absent,
             .failedRead: .foundOutcomeUnreadable(block)
        }
    }
}
