@testable import Coinage
import Foundation
import SubstrateSdk
import SubstrateOperation
import AsyncExtensions

/// Test stub for the block-outcome lookup closure ``BlockBodyScan`` scans with; records all
/// calls and returns configured responses.
///
/// Maps block hashes to their lookup outcomes. A hash absent from the map returns `.unreadable`.
actor StubBlockDataReader {
    private let lookups: [Data: BlockLookup]
    private(set) var reads: [Data] = []

    init(lookups: [Data: BlockLookup] = [:]) {
        self.lookups = lookups
    }

    func lookUp(_: Data, at blockHash: Data) async -> BlockLookup {
        reads.append(blockHash)
        return lookups[blockHash] ?? .unreadable
    }
}

/// Test stub for ``BlockInfoProviding`` that returns configured block hashes.
///
/// Throws when a block number is not in the configured mapping, simulating a failed
/// hash fetch.
final class StubBlockInfoProvider: BlockInfoProviding {
    private let hashes: [UInt32: Data]

    init(hashes: [UInt32: Data] = [:]) {
        self.hashes = hashes
    }

    func fetchCurrentHash() async throws -> BlockHashData {
        Data()
    }

    func fetchCurrent() async throws -> BlockNumber {
        BlockNumber(0)
    }

    func fetchFinalized() async throws -> BlockNumber {
        BlockNumber(0)
    }

    func fetchFinalizedHash() async throws -> BlockHashData {
        Data()
    }

    func fetchBlockHash(_ number: BlockNumber) async throws -> BlockHashData {
        guard let hash = hashes[UInt32(number)] else {
            throw BlockFetchError.blockNotFound
        }
        return hash
    }

    func subscribeFinalizedHeads() -> AnyAsyncSequence<Block.Header> {
        AsyncStream<Block.Header> { _ in }.eraseToAnyAsyncSequence()
    }

    func subscribeNewHeads() -> AnyAsyncSequence<Block.Header> {
        AsyncStream<Block.Header> { $0.finish() }.eraseToAnyAsyncSequence()
    }
}

private enum BlockFetchError: Error {
    case blockNotFound
}
