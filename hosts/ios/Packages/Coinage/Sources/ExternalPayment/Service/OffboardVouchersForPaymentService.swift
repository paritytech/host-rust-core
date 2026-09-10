import BigInt
import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import SubstrateSdk
import SubstrateOperation
import SubstrateSdkExt

/// Executes the offboarding flow: one extrinsic per recycler group, all registered atomically under
/// the payment id so the payment never leaves a half-committed group behind and a crash re-entry
/// re-joins the surviving group instead of re-registering claimed vouchers.
/// The transaction layer tracks the spent voucher inputs and surplus outputs; the surplus vouchers are
/// already persisted by the allocator when minted, so no local state bookkeeping is required.
///
/// Each group's call must independently satisfy the pallet invariant:
/// `input_value (= coin_value * alias_count) == external_asset_amount + sum(loaded_coin_values)`
///
/// Groups with surplus use `unload_recycler_into_external_asset_and_loaded_coins`.
/// Groups without surplus use `unload_recycler_into_external_asset`.
final class OffboardVouchersForPaymentService {
    private let instanceId: CoinageInstanceId
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let voucherMinter: any VoucherMinting
    private let recyclerLoader: RecyclerReadinessLoading
    private let txService: any CoinageTxServicing
    private let originFactory: OriginCreating
    private let quotaTracker: any UnloadQuotaTracking
    private let blockNumberProvider: BlockInfoProviding
    private let denominationContext: DenominationBreakdownContext
    private let logger: SDKLoggerProtocol?

    init(
        instanceId: CoinageInstanceId,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherMinter: any VoucherMinting,
        recyclerLoader: RecyclerReadinessLoading,
        txService: any CoinageTxServicing,
        originFactory: OriginCreating,
        quotaTracker: any UnloadQuotaTracking,
        blockNumberProvider: BlockInfoProviding,
        denominationContext: DenominationBreakdownContext,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.instanceId = instanceId
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherMinter = voucherMinter
        self.recyclerLoader = recyclerLoader
        self.txService = txService
        self.originFactory = originFactory
        self.quotaTracker = quotaTracker
        self.blockNumberProvider = blockNumberProvider
        self.denominationContext = denominationContext
        self.logger = logger
    }

    func execute(
        payment: ExternalPayment,
        vouchers: [Voucher]
    ) async throws -> OffboardOutcome {
        try await executeSubmissions(payment: payment, vouchers: vouchers)
    }

    /// Whether this payment already has a registered durability group — i.e. a prior attempt got as
    /// far as registration. Lets the state decide between re-joining and re-planning after a crash.
    func hasPendingGroup(for payment: ExternalPayment) async throws -> Bool {
        try await !txService.getOperationGroupStatuses(groupId(for: payment)).isEmpty
    }
}

/// The unload's single verdict, folded from its per-group entries. `partialSuccess` is not a
/// failure — money did move, just not all of it.
enum OffboardOutcome: Equatable {
    case success
    case partialSuccess(executed: Int, total: Int)
    case failed
}

// MARK: - Submission Pipeline

private extension OffboardVouchersForPaymentService {
    func executeSubmissions(
        payment: ExternalPayment,
        vouchers: [Voucher]
    ) async throws -> OffboardOutcome {
        let groupId = groupId(for: payment)

        try await registerOrRejoinGroup(payment: payment, vouchers: vouchers, groupId: groupId)

        return try await awaitGroupOutcome(groupId: groupId)
    }

    func groupId(for payment: ExternalPayment) -> CoinageTxGroupId {
        "external-payment:\(payment.id)"
    }

    /// Registers the whole payment as one atomic durability group, or re-joins the group a prior
    /// attempt already registered. Re-registering is impossible after a crash — the vouchers are
    /// claimed by the surviving entries — so on re-entry we adopt the group and await it.
    func registerOrRejoinGroup(
        payment: ExternalPayment,
        vouchers: [Voucher],
        groupId: CoinageTxGroupId
    ) async throws {
        let existing = try await txService.getOperationGroupStatuses(groupId)
        guard existing.isEmpty else {
            logger?.debug("Rejoining offboard group \(groupId): \(existing.count) entries")
            return
        }

        // Validation only guards the registration path — a re-join adopts already-committed inputs.
        guard !vouchers.isEmpty else { throw OffboardVouchersForPaymentError.emptyVouchers }
        guard !vouchers.contains(where: { $0.recycler == nil }) else {
            throw OffboardVouchersForPaymentError.missingRecyclerInfo
        }

        let requests = try await buildGroupRequests(payment: payment, vouchers: vouchers)
        _ = try await txService.submitTransactions(requests, groupId: groupId)
        logger?.debug("Registered \(requests.count) offboard groups under \(groupId)")

        // Each group spent one free-unload token; noted only on this registration path (a re-join
        // adopts already-committed inputs, whose tokens the original attempt already spent) and after
        // submission, so the quota estimate follows the actual spend.
        await quotaTracker.noteUnloadHappened(count: requests.count)
    }

    func awaitGroupOutcome(groupId: CoinageTxGroupId) async throws -> OffboardOutcome {
        for try await entries in txService.subscribeOperationGroupStatuses(groupId) {
            guard !entries.isEmpty, !entries.contains(where: \.status.isLive) else {
                continue
            }

            let executed = entries.filter { $0.status == .finalizedSuccess }.count
            let total = entries.count

            if executed == total {
                return .success
            } else if executed > 0 {
                return .partialSuccess(executed: executed, total: total)
            } else {
                return .failed
            }
        }

        throw OffboardVouchersForPaymentError.subscriptionEnded
    }

    func buildGroupRequests(
        payment: ExternalPayment,
        vouchers: [Voucher]
    ) async throws -> [CoinageTxRequest] {
        let details = try await buildGroupDetails(
            groups: groupVouchers(vouchers),
            paymentAmount: payment.amountInPlanks
        )

        let blockHash = try await blockNumberProvider.fetchCurrentHash()

        let origins = try await originFactory.createAsUnloadTokenOrigins(
            voucherGroups: details.map(\.group.vouchers),
            currentDate: Date(),
            blockHash: blockHash
        )

        let revisions = try await recyclerLoader.fetchRevisions(
            for: details.map(\.group.key),
            blockHash: blockHash
        )

        return try zip(details, origins).map { detail, origin in
            guard let revision = revisions[detail.group.key] else {
                throw OffboardVouchersForPaymentError.unexpectedEmptyRevision(detail.group.key)
            }

            return try buildRequest(GroupSubmission(
                details: detail,
                revision: revision,
                destination: payment.destination,
                origin: origin
            ))
        }
    }
}

// MARK: - Models

private extension OffboardVouchersForPaymentService {
    struct VoucherGroup {
        let key: RecyclerKey
        let vouchers: [Voucher]
    }

    struct GroupDetails {
        let group: VoucherGroup
        let externalAssetAmount: Balance
        let surplusVouchers: [Voucher]
    }

    struct GroupSubmission {
        let details: GroupDetails
        let revision: UInt32
        let destination: AccountId
        let origin: any ExtrinsicOriginDefining
    }

    /// The single group carrying the whole payment's surplus, and the change vouchers minted for it.
    struct SurplusHost {
        let hostKey: RecyclerKey
        let surplusVouchers: [Voucher]
    }
}

// MARK: - Per-Group Calculation

private extension OffboardVouchersForPaymentService {
    func buildGroupDetails(
        groups: [VoucherGroup],
        paymentAmount: Balance
    ) async throws -> [GroupDetails] {
        let totalInput = groups.reduce(Balance(0)) { $0 + groupInput($1) }
        let surplus = totalInput > paymentAmount ? totalInput - paymentAmount : Balance(0)

        let host = try await resolveSurplusHost(groups: groups, surplus: surplus)

        return groups.map { group in
            let isHost = group.key == host?.hostKey
            return GroupDetails(
                group: group,
                externalAssetAmount: isHost ? groupInput(group) - surplus : groupInput(group),
                surplusVouchers: isHost ? host?.surplusVouchers ?? [] : []
            )
        }
    }

    /// Picks the first group large enough to host the entire surplus and mints the change vouchers
    /// for it. `nil` when there is no surplus; throws when no single group can carry it.
    func resolveSurplusHost(
        groups: [VoucherGroup],
        surplus: Balance
    ) async throws -> SurplusHost? {
        guard surplus > 0 else { return nil }

        guard let host = groups.first(where: { groupInput($0) >= surplus }) else {
            throw OffboardVouchersForPaymentError.noSurplusHost(surplus)
        }

        let surplusVouchers = try await allocateSurplusVouchers(surplus: surplus)
        return SurplusHost(hostKey: host.key, surplusVouchers: surplusVouchers)
    }

    func groupInput(_ group: VoucherGroup) -> Balance {
        group.vouchers.reduce(Balance(0)) {
            $0 + denominationContext.valueInPlanks(for: $1.exponent)
        }
    }
}

// MARK: - Grouping

private extension OffboardVouchersForPaymentService {
    func groupVouchers(_ vouchers: [Voucher]) -> [VoucherGroup] {
        var grouped: [RecyclerKey: [Voucher]] = [:]
        for voucher in vouchers {
            guard let recycler = voucher.recycler else { continue }
            let key = RecyclerKey(exponent: voucher.exponent, index: recycler.index)
            grouped[key, default: []].append(voucher)
        }
        return grouped.map { VoucherGroup(key: $0.key, vouchers: $0.value) }
    }
}

// MARK: - Surplus

private extension OffboardVouchersForPaymentService {
    func allocateSurplusVouchers(surplus: Balance) async throws -> [Voucher] {
        guard surplus > 0 else { return [] }

        guard let surplusDecimal = Decimal.fromSubstrateAmount(
            surplus,
            precision: denominationContext.precision
        ) else {
            return []
        }

        let denominations = denominationContext.breakdown(amount: surplusDecimal)
        return try await voucherMinter.mintVouchers(denominations.map(\.exponent))
    }
}

// MARK: - Submission

private extension OffboardVouchersForPaymentService {
    func buildRequest(_ submission: GroupSubmission) throws -> CoinageTxRequest {
        let aliases = try submission.details.group.vouchers.map {
            try voucherKeyFactory.createKeyManager(for: $0)
                .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
        }

        let key = submission.details.group.key

        return CoinageTxRequest(
            inputs: submission.details.group.vouchers.map { .recyclerVoucher($0.derivationIndex, $0.publicKey) },
            outputs: submission.details.surplusVouchers
                .map { .recyclerVoucher($0.derivationIndex, $0.publicKey) },
            builder: { builder in
                if submission.details.surplusVouchers.isEmpty {
                    let call = self.buildExternalAssetCall(aliases: aliases, key: key, submission: submission)
                    return try builder.adding(call: call.callAsFunction())
                } else {
                    let call = try self.buildExternalAssetAndVouchersCall(
                        aliases: aliases,
                        key: key,
                        submission: submission
                    )

                    return try builder.adding(call: call.callAsFunction())
                }
            },
            origin: submission.origin
        )
    }

    func buildExternalAssetCall(
        aliases: [Data],
        key: RecyclerKey,
        submission: GroupSubmission
    ) -> CoinagePallet.Calls.UnloadRecyclerIntoExternalAsset {
        CoinagePallet.Calls.UnloadRecyclerIntoExternalAsset(
            instanceId: instanceId,
            aliases: aliases,
            value: Int8(key.exponent),
            index: key.index,
            revision: submission.revision,
            to: submission.destination
        )
    }

    func buildExternalAssetAndVouchersCall(
        aliases: [Data],
        key: RecyclerKey,
        submission: GroupSubmission
    ) throws -> CoinagePallet.Calls.UnloadRecyclerIntoExternalAssetAndLoadedCoins {
        let loadedCoinEntries = submission.details.surplusVouchers.map { voucher in
            CoinagePallet.Calls.UnloadRecyclerIntoExternalAssetAndLoadedCoins.LoadedCoin(
                coinValue: Int8(voucher.exponent),
                memberKey: voucher.publicKey
            )
        }

        return CoinagePallet.Calls.UnloadRecyclerIntoExternalAssetAndLoadedCoins(
            instanceId: instanceId,
            aliases: aliases,
            value: Int8(key.exponent),
            index: key.index,
            revision: submission.revision,
            to: submission.destination,
            externalAssetAmount: submission.details.externalAssetAmount,
            loadedCoins: loadedCoinEntries
        )
    }
}
