import AsyncExtensions
import Foundation
import NovaCrypto
import SDKLogger

public protocol CoinageTransferStatusServicing: Sendable {
    /// The derived payment status of each handed-off coin, keyed by public key. `coinKeys` are the
    /// secret keys carried in the transfer memo; their public keys are derived here.
    func subscribeStatuses(coinKeys: [Data]) -> AnyAsyncSequence<[PublicKey: CoinageTransferState]>
}

public final class CoinageTransferStatusService: CoinageTransferStatusServicing, @unchecked Sendable {
    private let databaseFactory: any DatabaseDependencyFactoring
    private let chainViewFactory: any CoinageChainViewFactoryProtocol
    private let coinOnChainQuery: any CoinOnChainQuerying
    private let snKeyFactory: any SNKeyFactoryProtocol
    private let logger: SDKLoggerProtocol?

    init(
        databaseFactory: any DatabaseDependencyFactoring,
        chainViewFactory: any CoinageChainViewFactoryProtocol,
        coinOnChainQuery: any CoinOnChainQuerying,
        snKeyFactory: any SNKeyFactoryProtocol,
        logger: SDKLoggerProtocol?
    ) {
        self.databaseFactory = databaseFactory
        self.chainViewFactory = chainViewFactory
        self.coinOnChainQuery = coinOnChainQuery
        self.snKeyFactory = snKeyFactory
        self.logger = logger
    }

    public func subscribeStatuses(coinKeys: [Data]) -> AnyAsyncSequence<[PublicKey: CoinageTransferState]> {
        let requested = coinKeys.compactMap { try? snKeyFactory.createPublicKey(fromSecret: $0).rawData() }
        // A filtered subscription to exactly these coins, not the whole set
        // `coinRepository.subscribeCoinsBy(accountIds)`.
        return databaseFactory.makeTrackedCoinSnapshotStream(publicKeys: requested)
            .map { [self] tracked -> [PublicKey: CoinageTransferState] in
                let atFinalized = await presenceAtFinalized(tracked)

                var result: [PublicKey: CoinageTransferState] = [:]
                for trackedCoin in tracked {
                    result[trackedCoin.coin.publicKey] = CoinageTransferState(
                        coin: trackedCoin.coin,
                        status: Self.transferStatus(trackedCoin, atFinalized: atFinalized)
                    )
                }
                return result
            }
            .eraseToAnyAsyncSequence()
    }
}

// MARK: - Ladder

extension CoinageTransferStatusService {
    static func transferStatus(_ tracked: TrackedCoin, atFinalized: [PublicKey: Bool]) -> CoinageTransferStatus {
        let coin = tracked.coin
        let state = tracked.state

        // Finalized minter and proven absent at finality: a guaranteed, terminal claim.
        if state.minterStatus == .finalizedSuccess, atFinalized[coin.publicKey] == false {
            return .claimed(finalized: true)
        }

        // Never minted: the key the peer holds controls nothing, and nothing will change that.
        if state.minterStatus == .failure {
            return .failed
        }

        if coin.isOnchain {
            return .awaitingClaim
        }

        // Seen on chain before, now gone, and its minter has arrived — the peer took it (best head).
        if coin.hasEverBeenOnChain, state.minterStatus?.isArrived == true {
            return .claimed(finalized: false)
        }

        // Absent on best but present at finality: cannot tell "not synced yet" from "gone", so play
        // safe and report awaiting; a later pass marks it claimed once it leaves the finalized block.
        if atFinalized[coin.publicKey] == true {
            return .awaitingClaim
        }

        return .detecting
    }

    /// Whether the finalized chain holds each coin whose mint finalized; absent from the map when
    /// unknown. Only those coins are worth asking about — one has to be minted beyond recall before
    /// its absence can mean the peer took it. A read that cannot be taken leaves them unknown.
    private func presenceAtFinalized(_ tracked: [TrackedCoin]) async -> [PublicKey: Bool] {
        let minted = tracked
            .filter { $0.state.minterStatus == .finalizedSuccess }
            .map(\.coin.publicKey)
        guard !minted.isEmpty else { return [:] }

        guard let view = try? await chainViewFactory.pin() else { return [:] }
        guard
            let responses = try? await coinOnChainQuery.fetchCoins(for: minted, atBlockHash: view.finalizedHead.hash),
            responses.count == minted.count
        else {
            return [:]
        }

        var presence: [PublicKey: Bool] = [:]
        for (key, response) in zip(minted, responses) {
            presence[key] = response != nil
        }
        return presence
    }
}
