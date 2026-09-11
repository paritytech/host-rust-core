import AsyncExtensions
import BigInt
import Foundation
import NovaCrypto
import os
import SDKLogger
import StructuredConcurrency
import SubstrateSdk

/// Claims coins a peer handed us, driven entirely off the durability group registered under
/// `groupId`.
///
/// Claiming is not one-shot: a coin the chain still shows unclaimed is money the peer has parted
/// with that nothing else will collect, so a failed claim is retried whenever the coin is still
/// there — until every coin has a finalized claim, or `retryUntil` passes. It always makes at least
/// one attempt, so a message first seen after its window closed is still tried once.
///
/// The flow completes only when nothing further will be attempted, so its completion is what tells a
/// caller the payment is finished — no interim detection means that.
public protocol ClaimCoinsServicing: Sendable {
    func claim(
        coinKeys: [Data],
        groupId: CoinageTxGroupId,
        retryUntil: Date,
        context: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection>
}

public final class ClaimCoinsService: ClaimCoinsServicing, @unchecked Sendable {
    /// How long one pass waits for every coin to show up before claiming whatever it can see. A
    /// peer's coin has no ledger row of ours, so only the chain can say it exists, and one that never
    /// arrives must not hold up the ones that did.
    private static let detectionTimeout: Duration = .seconds(30)

    private let txService: any CoinageTxServicing
    private let coinOnChainQuery: any CoinOnChainQuerying
    private let claimSubmitter: any CoinageClaimSubmitting
    private let snKeyFactory: any SNKeyFactoryProtocol
    private let coinService: any CoinServiceProtocol
    private let logger: SDKLoggerProtocol?

    init(
        txService: any CoinageTxServicing,
        coinOnChainQuery: any CoinOnChainQuerying,
        claimSubmitter: any CoinageClaimSubmitting,
        snKeyFactory: any SNKeyFactoryProtocol,
        coinService: any CoinServiceProtocol,
        logger: SDKLoggerProtocol?
    ) {
        self.txService = txService
        self.coinOnChainQuery = coinOnChainQuery
        self.claimSubmitter = claimSubmitter
        self.snKeyFactory = snKeyFactory
        self.coinService = coinService
        self.logger = logger
    }

    public func claim(
        coinKeys: [Data],
        groupId: CoinageTxGroupId,
        retryUntil: Date,
        context: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection> {
        AsyncStream { continuation in
            let task = Task {
                await self.runClaim(
                    coinKeys: coinKeys,
                    groupId: groupId,
                    retryUntil: retryUntil,
                    context: context
                ) { detection in
                    continuation.yield(detection)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyAsyncSequence()
    }
}

// MARK: - Claim loop

private extension ClaimCoinsService {
    func runClaim(
        coinKeys: [Data],
        groupId: CoinageTxGroupId,
        retryUntil: Date,
        context: DenominationBreakdownContext,
        report: @Sendable (CoinageTransferDetection) -> Void
    ) async {
        report(.detecting)

        let keypairs = deriveKeypairs(from: coinKeys)
        let coins = Set(keypairs.keys)
        guard !coins.isEmpty else { report(.notClaimed); return }

        let onChainUpdates = AsyncBufferedChannel<[PublicKey: Int16]>()
        let pump = Task { [coinOnChainQuery] in
            do {
                for try await snapshot in coinOnChainQuery.subscribeCoinInfos(for: Array(coins)) {
                    onChainUpdates.send(snapshot)
                }
            } catch {}
        }
        defer { pump.cancel() }
        let onChain = onChainUpdates.makeAsyncIterator()

        var settled: [CoinageTxEntry] = []

        logger?.debug("Will start claiming coins with group=\(groupId)")

        while !Task.isCancelled {
            logger?.debug("Awaiting settles coins=\(coins.count) with group=\(groupId)")

            settled = await awaitKnownOperationsSettled(
                groupId: groupId, coins: coins, context: context, report: report
            )
            let unclaimed = coins.subtracting(settled.finalizedSuccess().receivedPublicKeys())
            if unclaimed.isEmpty {
                logger?.debug("All coins claimed group=\(groupId)")
                break
            }

            logger?.debug("Unclaimed \(unclaimed.count) coins for group=\(groupId)")

            let claimable = await awaitOnChainWithTimeout(onChain, unclaimed: unclaimed)

            logger?.debug("Claimable \(claimable.count) coins for group=\(groupId)")

            if !claimable.isEmpty {
                logger?.debug("Claiming coins for group=\(groupId)")

                await submit(claimable: claimable, keypairs: keypairs, groupId: groupId)

                logger?.debug("Claiming complete for group=\(groupId)")
            } else if Date() >= retryUntil {
                logger?.debug("Claim window closed group=\(groupId) unclaimed=\(unclaimed.count)")
                break
            }
        }

        await report(toVerdict(settled, coins: coins, context: context))
    }

    /// Reports the group on every ledger update until nothing in it is live, then returns what it
    /// settled on. An empty group is already settled — a first attempt, nothing to wait for.
    func awaitKnownOperationsSettled(
        groupId: CoinageTxGroupId,
        coins: Set<PublicKey>,
        context: DenominationBreakdownContext,
        report: @Sendable (CoinageTransferDetection) -> Void
    ) async -> [CoinageTxEntry] {
        var last: [CoinageTxEntry] = []
        do {
            for try await states in txService.subscribeOperationGroupStatuses(groupId) {
                last = states
                await report(toProgress(states, coins: coins, context: context))
                if states.allSatisfy({ !$0.status.isLive }) { break }
            }
        } catch {
            logger?.error("Claim group-status stream failed group=\(groupId): \(error)")
        }
        return last
    }

    func submit(claimable: [PublicKey: Int16], keypairs: [PublicKey: Data], groupId: CoinageTxGroupId) async {
        let items = claimable.compactMap { key, exponent -> ClaimableCoin? in
            guard let privateKey = keypairs[key] else { return nil }
            return ClaimableCoin(privateKey: privateKey, publicKey: key, valueExponent: exponent)
        }
        do {
            try await claimSubmitter.submit(claimable: items, groupId: groupId)
        } catch {
            logger?.error("Claim submission failed group=\(groupId): \(error)")
        }
    }

    /// The next look at the chain that shows every still-owed coin, or the best look within
    /// ``detectionTimeout``. Reads the consume-once channel one look at a time, so a failing submit
    /// cannot spin the loop. Settling for the last look is deliberate: a coin that never arrives is
    /// the peer's problem, and holding the others hostage to it would strand money sitting right there.
    func awaitOnChainWithTimeout(
        _ onChain: AsyncBufferedChannel<[PublicKey: Int16]>.Iterator,
        unclaimed: Set<PublicKey>
    ) async -> [PublicKey: Int16] {
        let latest = OSAllocatedUnfairLock<[PublicKey: Int16]>(initialState: [:])
        _ = try? await withTimeout(Self.detectionTimeout) {
            while let look = await onChain.next() {
                let filtered = look.filter { unclaimed.contains($0.key) }
                latest.withLock { $0 = filtered }
                if unclaimed.isSubset(of: Set(filtered.keys)) { break }
            }
        }
        return latest.withLock { $0 }
    }

    func deriveKeypairs(from coinKeys: [Data]) -> [PublicKey: Data] {
        var result: [PublicKey: Data] = [:]
        for key in coinKeys {
            guard let publicKey = try? snKeyFactory.createPublicKey(fromSecret: key).rawData() else {
                logger?.warning("Claim: failed to derive public key for a coin key")
                continue
            }
            result[publicKey] = key
        }
        return result
    }
}

// MARK: - Detection

private extension ClaimCoinsService {
    /// What is true right now, reported on every ledger update. Nothing here may say claiming is
    /// over — only the loop knows that — so a shortfall is never announced while a retry could make it up.
    func toProgress(
        _ states: [CoinageTxEntry],
        coins: Set<PublicKey>,
        context: DenominationBreakdownContext
    ) async -> CoinageTransferDetection {
        let arrived = states.filter(\.status.isArrived)
        let outstanding = coins.subtracting(arrived.receivedPublicKeys())

        if outstanding.isEmpty {
            let finalized = coins.subtracting(states.finalizedSuccess().receivedPublicKeys()).isEmpty
            return await .claimed(amount: valueMinted(by: arrived, context: context), finalized: finalized)
        }

        let failed = states.filter { $0.status == .failure }.receivedPublicKeys()
        if !arrived.isEmpty, outstanding.contains(where: { failed.contains($0) }) {
            return await .claimingRest(claimed: valueMinted(by: arrived, context: context))
        }

        return states.isEmpty ? .detecting : .claiming
    }

    /// The last word, once nothing further will be attempted — the only place a shortfall may be final.
    func toVerdict(
        _ states: [CoinageTxEntry],
        coins: Set<PublicKey>,
        context: DenominationBreakdownContext
    ) async -> CoinageTransferDetection {
        let arrived = states.filter(\.status.isArrived)
        let notArrived = coins.subtracting(arrived.receivedPublicKeys())

        if notArrived.isEmpty {
            let finalized = coins.subtracting(states.finalizedSuccess().receivedPublicKeys()).isEmpty
            return await .claimed(amount: valueMinted(by: arrived, context: context), finalized: finalized)
        }
        if !arrived.isEmpty {
            return await .claimedPartially(claimed: valueMinted(by: arrived, context: context))
        }
        return .notClaimed
    }

    /// The planks minted by `entries` — their output coins valued against the denomination context.
    func valueMinted(by entries: [CoinageTxEntry], context: DenominationBreakdownContext) async -> Balance {
        let outputKeys = entries.outputPublicKeys()

        guard !outputKeys.isEmpty else { return 0 }

        let coins = await (try? coinService.fetchCoins(publicKeys: outputKeys)) ?? []
        return coins.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }
}
