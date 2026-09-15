import AsyncExtensions
import Coinage
import Foundation
import SubstrateSdk

/// A test fake that is both a `CoinageChainViewProtocol` (a pinned view) and its
/// `CoinageChainViewFactoryProtocol` (self-pinning: `pin()` returns itself), so a test injects one
/// object wherever the engine expects either.
///
/// Default behaviour for any unconfigured read is `absent`; tests must opt in to presence. The
/// pinned heads are whatever the test last set via ``setChainView(finalized:best:)``.
final class FakeChainView: CoinageChainViewProtocol, CoinageChainViewFactoryProtocol, @unchecked Sendable {
    private var checkpoints: ChainView
    private var inputResults: [UInt32: [ReadResult<AssetPresence>]] = [:]
    private var outputResults: [UInt32: [ReadResult<AssetPresence>]] = [:]
    private var hashResults: [UInt32: ReadResult<Data>] = [:]
    private var refResults: [Data: ReadResult<BlockRef>] = [:]
    private var outcomeResults: [UInt32: [Data: ReadResult<Bool>]] = [:]
    private var bodySearchResponses: [Data: BodySearchOutcome] = [:]

    init(
        finalized: BlockRef = BlockRef(number: 100, hash: Data([100])),
        best: BlockRef = BlockRef(number: 110, hash: Data([110]))
    ) {
        checkpoints = ChainView(finalized: finalized, best: best)
    }

    var finalizedHead: BlockRef { checkpoints.finalized }
    var bestHead: BlockRef { checkpoints.best }

    // MARK: - Configuration API

    func setChainView(finalized: BlockRef, best: BlockRef) {
        checkpoints = ChainView(finalized: finalized, best: best)
    }

    func setInputPresence(at block: BlockRef, to results: [ReadResult<AssetPresence>]) {
        inputResults[block.number] = results
    }

    func setOutputPresence(at block: BlockRef, to results: [ReadResult<AssetPresence>]) {
        outputResults[block.number] = results
    }

    func setBlockHash(_ hash: Data, forNumber number: UInt32) {
        hashResults[number] = .present(hash)
    }

    func setBlockHashFailed(_ number: UInt32) {
        hashResults[number] = .failedRead
    }

    func setBlockRef(_ ref: BlockRef) {
        refResults[ref.hash] = .present(ref)
    }

    func setBlockRefFailed(_ hash: Data) {
        refResults[hash] = .failedRead
    }

    func setDispatchOutcome(_ txHash: Data, at block: BlockRef, success: Bool) {
        outcomeResults[block.number, default: [:]][txHash] = .present(success)
    }

    func setDispatchOutcomeFailed(_ txHash: Data, at block: BlockRef) {
        outcomeResults[block.number, default: [:]][txHash] = .failedRead
    }

    func setBodySearchResponse(_ txHash: Data, to outcome: BodySearchOutcome) {
        bodySearchResponses[txHash] = outcome
    }

    // MARK: - CoinageChainViewFactoryProtocol

    private(set) var pinCount = 0

    func pin() async throws -> any CoinageChainViewProtocol {
        pinCount += 1
        return self
    }

    func finalizedHeads() -> AnyAsyncSequence<BlockNumber> {
        AsyncStream<BlockNumber> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func bestHeads() -> AnyAsyncSequence<BlockNumber> {
        AsyncStream<BlockNumber> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    // MARK: - CoinageChainViewProtocol

    func readInputs(_ inputs: [CoinageTxInput], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        inputResults[block.number] ?? Array(repeating: .absent, count: inputs.count)
    }

    func readOutputs(_ outputs: [OwnAsset], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        outputResults[block.number] ?? Array(repeating: .absent, count: outputs.count)
    }

    func blockHash(at number: UInt32) async -> ReadResult<Data> {
        hashResults[number] ?? .absent
    }

    func blockRef(forHash hash: Data) async -> ReadResult<BlockRef> {
        refResults[hash] ?? .absent
    }

    func dispatchOutcome(txHash: Data, at block: BlockRef) async -> ReadResult<Bool> {
        (outcomeResults[block.number] ?? [:])[txHash] ?? .absent
    }

    private(set) var searchedHashes: [Data] = []

    func searchBodies(for txHash: Data, in _: ClosedRange<UInt32>) async -> BodySearchOutcome {
        searchedHashes.append(txHash)
        return bodySearchResponses[txHash] ?? .notFoundWindowComplete
    }
}
