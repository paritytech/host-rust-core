import Foundation
@testable import Coinage

/// One block: its number and hash, the transactions it carries, and the full chain state as of it.
struct FakeBlock {
    let number: UInt32
    let hash: Data
    let parentHash: Data
    let state: CoinageChainState
    let body: [Data]
}

/// A block tree with per-block state, finalization and reorgs.
///
/// Reorged-out blocks stay readable by hash, the way a node still serves an orphaned block; only the
/// canonical chain moves. `reorgDepths` is bounded by the unfinalized suffix, so a finalized block
/// cannot be reorged and no failure a fuzzer finds is merely a violated requirement.
///
/// Every produced block gets a fresh, unique hash, so a reorg followed by a replacing branch of the
/// same height still changes the canonical hash at that height — which is exactly what lets
/// `recordedBlockStillCanonical` flip to false.
final class FakeChain: @unchecked Sendable {
    private var byHash: [Data: FakeBlock] = [:]
    private var canonical: [FakeBlock] = []
    private var nextHashSeq: UInt64 = 0
    private var finalizedNumber: UInt32 = 0

    init(initialState: CoinageChainState) {
        let genesis = FakeBlock(
            number: 0,
            hash: freshHash(),
            parentHash: Data(),
            state: initialState,
            body: []
        )
        byHash[genesis.hash] = genesis
        canonical.append(genesis)
    }

    var bestHead: FakeBlock { canonical[canonical.count - 1] }

    var finalizedHead: FakeBlock { canonical[Int(finalizedNumber)] }

    /// Empty when nothing is unfinalized, which is what makes a finalized block unreorgable.
    var reorgDepths: [Int] {
        let span = Int(bestHead.number) - Int(finalizedNumber)
        guard span >= 1 else { return [] }
        return Array(1 ... span)
    }

    @discardableResult
    func produceBlock(body: [Data] = [], mutate: (CoinageChainState) -> CoinageChainState = { $0 }) -> FakeBlock {
        let parent = bestHead
        let block = FakeBlock(
            number: parent.number + 1,
            hash: freshHash(),
            parentHash: parent.hash,
            state: mutate(parent.state),
            body: body
        )
        byHash[block.hash] = block
        canonical.append(block)
        return block
    }

    func finalize(upTo number: UInt32) {
        let clamped = min(number, bestHead.number)
        finalizedNumber = max(finalizedNumber, clamped)
    }

    /// Rewinds the canonical head by `depth`; the caller produces the replacing branch. The dropped
    /// blocks stay readable by hash.
    func reorg(depth: Int) {
        guard reorgDepths.contains(depth) else { return }
        canonical.removeLast(depth)
    }

    func stateAt(hash: Data) -> CoinageChainState? { byHash[hash]?.state }

    func blockAt(hash: Data) -> FakeBlock? { byHash[hash] }

    func canonicalAt(_ number: UInt32) -> FakeBlock? {
        Int(number) < canonical.count ? canonical[Int(number)] : nil
    }

    private func freshHash() -> Data {
        defer { nextHashSeq += 1 }
        var bytes = [UInt8](repeating: 0, count: 32)
        var seq = nextHashSeq
        for offset in 0 ..< 8 {
            bytes[31 - offset] = UInt8(truncatingIfNeeded: seq)
            seq >>= 8
        }
        return Data(bytes)
    }
}
