import Foundation
import ExtrinsicService
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt
import KeyDerivation
import BigInt
import SDKLogger
import SubstrateOperation

/// Strategy 3: Unload vouchers directly into required denominations.
///
/// Submits one extrinsic per recycler group. `CoinSelector` guarantees each group
/// respects the `maxConsolidation` pallet constraint (throws if exceeded). All groups
/// run concurrently — one task per `RecyclerKey`.
struct UnloadIntoCoinsStrategy {
    private let instanceId: CoinageInstanceId
    private let readyCoins: [Coin]
    private let perGroupAllocations: [RecyclerGroupAllocation]
    private let minter: any CoinMinting
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let recyclerLoader: RecyclerReadinessLoading
    private let txService: any CoinageTxServicing
    private let originFactory: OriginCreating
    private let quotaTracker: any UnloadQuotaTracking
    private let blockInfoProvider: any BlockInfoProviding
    private let currentDate: Date
    private let logger: SDKLoggerProtocol?

    init(
        instanceId: CoinageInstanceId,
        readyCoins: [Coin],
        perGroupAllocations: [RecyclerGroupAllocation],
        minter: any CoinMinting,
        voucherKeyFactory: any VoucherKeyDeriving,
        recyclerLoader: RecyclerReadinessLoading,
        txService: any CoinageTxServicing,
        originFactory: OriginCreating,
        quotaTracker: any UnloadQuotaTracking,
        blockInfoProvider: any BlockInfoProviding,
        currentDate: Date,
        logger: SDKLoggerProtocol?
    ) {
        self.instanceId = instanceId
        self.readyCoins = readyCoins
        self.perGroupAllocations = perGroupAllocations
        self.minter = minter
        self.voucherKeyFactory = voucherKeyFactory
        self.recyclerLoader = recyclerLoader
        self.txService = txService
        self.originFactory = originFactory
        self.quotaTracker = quotaTracker
        self.blockInfoProvider = blockInfoProvider
        self.currentDate = currentDate
        self.logger = logger
    }
}

// MARK: - TransferStrategy

extension UnloadIntoCoinsStrategy: TransferStrategy {
    func prepare(groupId: CoinageTxGroupId?) async throws -> PreparedStrategy {
        guard !perGroupAllocations.isEmpty else {
            throw TransferStrategyError.emptyVouchers
        }

        let allVouchers = perGroupAllocations.flatMap(\.vouchers)

        guard !allVouchers.contains(where: { $0.recycler == nil }) else {
            throw TransferStrategyError.missingRecyclerInfo
        }

        var realizedGroups: [RecyclerGroupCoins] = []
        for allocation in perGroupAllocations {
            // Every voucher in an allocation sits in the same recycler, so they carry the same
            // score; the minimum is a tie-break for readings taken a tick apart.
            let provenance = CoinProvenance.unloaded(
                recyclerFungibility: allocation.vouchers.map(\.recyclerFungibility).min()
            )

            let recipientCoins = try await minter
                .mintCoins(allocation.recipientDenominations.map(\.exponent), provenance: provenance)
            let changeCoins = try await minter
                .mintCoins(allocation.changeDenominations.map(\.exponent), provenance: provenance)
            realizedGroups.append(RecyclerGroupCoins(
                recyclerKey: allocation.recyclerKey,
                vouchers: allocation.vouchers,
                recipientCoins: recipientCoins,
                changeCoins: changeCoins
            ))
        }

        // Fetch on-chain state and build every group's request before submitting any, so a build
        // failure aborts before a single extrinsic is broadcast.
        let requests = try await buildRequests(for: realizedGroups)

        // Register all groups atomically under the transfer's groupId
        logger?.info("Submitting \(requests.count) unload extrinsics for \(allVouchers.count) vouchers")
        try await txService.submitTransactions(
            requests.map {
                CoinageTxRequest(inputs: $0.inputs, outputs: $0.outputs, builder: $0.builder, origin: $0.origin)
            },
            groupId: groupId
        )

        // Each group spent one free-unload token; note them after submission (a token for a tx that
        // never left is still available) so the quota estimate follows the actual spend.
        await quotaTracker.noteUnloadHappened(count: requests.count)

        // Ready coins need no submission; every group's recipient coins leave to the peer. Change
        // coins stay ours. All pre-committed before the memo can leave.
        let handedOff = readyCoins + realizedGroups.flatMap(\.recipientCoins)
        let handoffCommit = try await txService
            .preCommitHandoff(handedOff.map { .coin($0.derivationIndex, $0.publicKey) })

        var memoEntries = readyCoins.map {
            PlannedMemoEntry(
                coinDerivationIndex: $0.derivationIndex,
                valueExponent: $0.exponent
            )
        }
        for group in realizedGroups {
            memoEntries += group.recipientCoins.map {
                PlannedMemoEntry(
                    coinDerivationIndex: $0.derivationIndex, valueExponent: $0.exponent
                )
            }
        }

        return PreparedStrategy(memoEntries: memoEntries, handoffCommit: handoffCommit)
    }
}

// MARK: - Private Helpers

private extension UnloadIntoCoinsStrategy {
    struct GroupRequest {
        let inputs: [CoinageTxInput]
        let outputs: [OwnAsset]
        let builder: ExtrinsicBuilderClosure
        let origin: any ExtrinsicOriginDefining
    }

    /// Fetches on-chain state (finalized block hash, unload-token origins, recycler revisions) and
    /// builds one request per group. Nothing is submitted here, so a build failure aborts the whole
    /// transfer before any extrinsic goes on the wire.
    func buildRequests(for realizedGroups: [RecyclerGroupCoins]) async throws -> [GroupRequest] {
        // Fetch finalized block hash upfront to ensure both operations query the same state.
        let blockHash = try await blockInfoProvider.fetchCurrentHash()

        // Create all origins upfront — each group needs a distinct unload token.
        let origins = try await originFactory.createAsUnloadTokenOrigins(
            voucherGroups: realizedGroups.map(\.vouchers),
            currentDate: currentDate,
            blockHash: blockHash
        )
        guard origins.count == realizedGroups.count else {
            assertionFailure("Origin for recycler group is missing")
            throw TransferStrategyError.invalidRecyclerRevision
        }

        let keys = realizedGroups.map(\.recyclerKey)
        let revisions = try await recyclerLoader.fetchRevisions(for: keys, blockHash: blockHash)
        guard keys.count == revisions.count else {
            assertionFailure("Revision for recyclerKey is missing")
            throw TransferStrategyError.invalidRecyclerRevision
        }

        return try zip(realizedGroups, origins).map { groupCoins, origin in
            let revision = revisions[groupCoins.recyclerKey]! // validated above
            let call = try buildCall(for: groupCoins, revision: revision)
            return GroupRequest(
                inputs: groupCoins.vouchers.map { .recyclerVoucher($0.derivationIndex, $0.publicKey) },
                outputs: (groupCoins.recipientCoins + groupCoins.changeCoins)
                    .map { .coin($0.derivationIndex, $0.publicKey) },
                builder: { try $0.adding(call: call.callAsFunction()) },
                origin: origin
            )
        }
    }

    func buildCall(
        for groupCoins: RecyclerGroupCoins,
        revision: UInt32
    ) throws -> CoinagePallet.Calls.UnloadRecyclerIntoCoins {
        let key = groupCoins.recyclerKey

        let aliases = try groupCoins.vouchers.map {
            try voucherKeyFactory.createKeyManager(for: $0)
                .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
        }

        var destGrouped: [Int16: [Data]] = [:]
        for coin in groupCoins.recipientCoins + groupCoins.changeCoins {
            destGrouped[coin.exponent, default: []].append(coin.publicKey)
        }
        let destinations = destGrouped.map { exponent, accounts in
            CoinagePallet.Calls.Split.SplitDestination(exponent: exponent, accounts: accounts)
        }

        return CoinagePallet.Calls.UnloadRecyclerIntoCoins(
            instanceId: instanceId,
            aliases: aliases,
            value: Int8(key.exponent),
            index: key.index,
            revision: revision,
            splitInto: destinations.sorted { $0.exponent < $1.exponent }
        )
    }
}
