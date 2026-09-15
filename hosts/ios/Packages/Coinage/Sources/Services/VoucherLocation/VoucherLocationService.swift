import Foundation
import BandersnatchApi
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality
import ExtrinsicService
import StructuredConcurrency
import Operation_iOS
import BigInt
import SDKLogger
import KeyDerivation
import AsyncExtensions
import CommonService
import OperationExt
import os

/// A service that monitors local vouchers and synchronizes their on-chain status.
///
/// Tracks every voucher the durability layer still cares about (`shouldTrackOnchain` — not spent, not
/// mint-failed), not just those outside a recycler: a ring keeps filling after a voucher lands in it, and
/// the member count is what the strategies read to decide when it may be spent. Two-phase per batch, held
/// together entirely by stream operators rather than in-memory
/// reconciliation:
/// 1. **Members**: subscribe `Members[collection][voucherPubKey]` for every voucher and `scan` the
///    per-key deltas into a complete positions snapshot.
/// 2. **RingKeysStatus**: `flatMapLatest` re-derives the ring-status subscription from the current
///    positions and `scan`s its deltas into a complete status snapshot, then joins the two snapshots into
///    the resolved location — onboarding, or in-recycler(ringIndex, ringMembers).
public final class VoucherLocationService: BaseSyncService {
    private let instanceId: CoinageInstanceId
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let databaseFactory: any DatabaseDependencyFactoring
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol

    private var localVouchersMonitoringTask: Task<Void, Error>?
    private var voucherStatusSubscriptionTask: Task<Void, Error>?

    public init(
        instanceId: CoinageInstanceId,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        databaseFactory: any DatabaseDependencyFactoring,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        logger: any SDKLoggerProtocol
    ) {
        self.instanceId = instanceId
        self.voucherRepository = voucherRepository
        self.databaseFactory = databaseFactory
        self.connection = connection
        self.runtimeService = runtimeService
        super.init(logger: logger)
    }

    deinit {
        stopSyncUp()
    }

    /// Begins monitoring the local database for vouchers worth tracking on chain (`shouldTrackOnchain`),
    /// resolving their location (onboarding → in-recycler) and refreshing the ring member count.
    override public func performSyncUp() {
        localVouchersMonitoringTask = Task { [weak self] in
            guard let self else { return }

            let stream = databaseFactory.makeTrackedVoucherSnapshotStream()
                .map { trackedVouchers in
                    trackedVouchers.filter(\.shouldTrackOnchain).map(\.voucher)
                }
                // Resubscribe only when the tracked key-set changes; non-key voucher edits keep the
                // existing subscription.
                .removeDuplicates { previous, current in
                    Set(previous.map(\.publicKey)) == Set(current.map(\.publicKey))
                }

            for try await vouchers in stream {
                voucherStatusSubscriptionTask?.cancel()

                guard !vouchers.isEmpty else {
                    logger.debug("Voucher sync stopped")
                    continue
                }
                try Task.checkCancellation()

                logger.debug("Voucher sync started: \(vouchers.count)")
                startLocationSync(for: vouchers)
            }
        }
    }

    override public func stopSyncUp() {
        localVouchersMonitoringTask?.cancel()
        voucherStatusSubscriptionTask?.cancel()
    }
}

extension VoucherLocationService {
    private func startLocationSync(for vouchers: [Voucher]) {
        voucherStatusSubscriptionTask = Task { [weak self] in
            do {
                try await self?.runLocationPipeline(for: vouchers)
            } catch is CancellationError {
                // Expected: superseded by a newer tracked-voucher set.
            } catch {
                self?.logger.error("Voucher sync failed during monitoring: \(error)")
            }
        }
    }

    /// The reactive two-phase pipeline. `scan` keeps a complete positions snapshot up to date from the
    /// member subscription's deltas; `flatMapLatest` re-derives the ring-status subscription whenever the
    /// positions change and `scan`s its deltas into a complete status snapshot. Joining the two is a pure
    /// function, so nothing needs to be reconciled by hand between emissions.
    private func runLocationPipeline(for vouchers: [Voucher]) async throws {
        let memberReqs = try memberRequests(vouchers)
        guard !memberReqs.isEmpty else { return }

        let memberStream: AnyAsyncSequence<MemberStatusResult> = CallbackBatchStorageSubscription
            .asyncStream(
                requests: memberReqs,
                connection: connection,
                runtimeService: runtimeService,
                logger: logger
            )

        let positionsStream = memberStream
            .scan([DerivationIndex: UncertainStorage<MembersPallet.RingPosition?>]()) { positions, result in
                var positions = positions
                for update in result.ringPositionUpdates {
                    // The update was delivered, so it is `.defined`; a delivered empty reading is
                    // `.defined(nil)` (retraction) rather than a dropped key, so it can revert the voucher.
                    // A key never delivered stays absent — that, not `.undefined`, is "not changed".
                    positions[update.derivationIndex] = .defined(update.ringPosition)
                }
                return positions
            }

        let resolvedStream = positionsStream
            .flatMapLatest { [weak self] positions -> AnyAsyncSequence<[DerivationIndex: Voucher.OnChainState]> in
                guard let self else {
                    return AsyncEmptySequence().eraseToAnyAsyncSequence()
                }
                return resolvedLocationsStream(positions: positions, vouchers: vouchers)
            }
            .removeDuplicates { $0 == $1 }

        for try await locations in resolvedStream {
            try Task.checkCancellation()
            try await writeLocations(locations)
        }
    }

    /// Subscribes to `RingKeysStatus` for the rings the current positions land in, `scan`s the deltas into
    /// a complete status snapshot, and resolves each voucher's location against it. When no voucher is yet
    /// placed in a ring, emits the onboarding-only resolution once so those writes still happen.
    private func resolvedLocationsStream(
        positions: [DerivationIndex: UncertainStorage<MembersPallet.RingPosition?>],
        vouchers: [Voucher]
    ) -> AnyAsyncSequence<[DerivationIndex: Voucher.OnChainState]> {
        let voucherByIndex = Dictionary(uniqueKeysWithValues: vouchers.map { ($0.derivationIndex, $0) })
        let requests = ringStatusRequests(positions: positions, voucherByIndex: voucherByIndex)

        guard !requests.isEmpty else {
            let resolved = Self.resolveLocations(positions: positions, statuses: [:])
            return AsyncJustSequence(resolved).eraseToAnyAsyncSequence()
        }

        let statusStream: AnyAsyncSequence<MemberStatusResult> = CallbackBatchStorageSubscription
            .asyncStream(
                requests: requests,
                connection: connection,
                runtimeService: runtimeService,
                logger: logger
            )

        return statusStream
            .scan([DerivationIndex: UncertainStorage<MembersPallet.RingKeysStatus?>]()) { statuses, result in
                var statuses = statuses
                for update in result.ringStatusUpdates {
                    statuses[update.derivationIndex] = .defined(update.ringKeysStatus)
                }
                return statuses
            }
            .map { Self.resolveLocations(positions: positions, statuses: $0) }
            .eraseToAnyAsyncSequence()
    }
}

// MARK: - Requests

private extension VoucherLocationService {
    /// Subscribes to `Members[identifier][voucherPubKey]` for every tracked voucher — including those
    /// already in a recycler, so a ring that keeps filling refreshes the voucher's position and member
    /// count. Detects Onboarding -> Included transitions and in-ring member growth.
    func memberRequests(_ vouchers: [Voucher]) throws -> [BatchStorageSubscriptionRequest] {
        vouchers.map { voucher in
            let publicKey = voucher.publicKey
            let collectionId = RecyclerCollectionIdentifier.identifier(instanceId: instanceId, for: voucher.exponent)
            let mappingKey = SubscriptionKey.member(derivationIndex: voucher.derivationIndex).mappingKey

            let innerRequest = DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.members(),
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: collectionId),
                        BytesCodable(wrappedValue: publicKey)
                    )
                }
            )

            return BatchStorageSubscriptionRequest(innerRequest: innerRequest, mappingKey: mappingKey)
        }
    }

    func ringStatusRequests(
        positions: [DerivationIndex: UncertainStorage<MembersPallet.RingPosition?>],
        voucherByIndex: [DerivationIndex: Voucher]
    ) -> [BatchStorageSubscriptionRequest] {
        positions.compactMap { derivationIndex, entry -> BatchStorageSubscriptionRequest? in
            guard case let .defined(.some(position)) = entry,
                  let ringIndex = position.ringIndex,
                  let voucher = voucherByIndex[derivationIndex]
            else { return nil }

            let collectionId = RecyclerCollectionIdentifier.identifier(instanceId: instanceId, for: voucher.exponent)
            let mappingKey = SubscriptionKey.ringStatus(derivationIndex: derivationIndex).mappingKey

            let innerRequest = DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.ringKeysStatus(),
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: collectionId),
                        StringCodable(wrappedValue: ringIndex)
                    )
                }
            )

            return BatchStorageSubscriptionRequest(innerRequest: innerRequest, mappingKey: mappingKey)
        }
    }
}

// MARK: - Resolution

extension VoucherLocationService {
    /// Pure join of the two snapshots into the location each voucher should be persisted with.
    ///
    /// The snapshots are read three ways: a key absent from the map (or ``UncertainStorage/undefined``) was
    /// not delivered in the subscription and is left untouched; a ``UncertainStorage/defined(_:)`` with a
    /// `nil` reading was delivered empty (absent on chain or retracted by a fork); and a `.defined` with a
    /// value carries it.
    ///
    /// - A member row delivered empty (`.defined(nil)`, retracted) reverts the voucher to `.unlocated` — the
    ///   fix for the case a fork drops a member and the stale in-recycler state would otherwise linger.
    /// - An included voucher whose ring status confirms its key becomes in-recycler with the real member
    ///   count; if that ring status is delivered empty (the ring was retracted) the voucher falls back to
    ///   onboarding.
    /// - A status not delivered yet leaves the voucher deferred (no entry emitted) rather than guessed at.
    /// - Anything else (onboarding/suspended position) is onboarding.
    static func resolveLocations(
        positions: [DerivationIndex: UncertainStorage<MembersPallet.RingPosition?>],
        statuses: [DerivationIndex: UncertainStorage<MembersPallet.RingKeysStatus?>]
    ) -> [DerivationIndex: Voucher.OnChainState] {
        positions.reduce(into: [:]) { resolved, entry in
            let (derivationIndex, positionEntry) = entry

            // Not delivered — leave the voucher as it is.
            guard case let .defined(deliveredPosition) = positionEntry else { return }

            // Delivered empty — the member row was retracted; revert to unlocated.
            guard let position = deliveredPosition else {
                resolved[derivationIndex] = .unlocated
                return
            }

            guard let ringIndex = position.ringIndex else {
                resolved[derivationIndex] = .onboarding
                return
            }

            switch statuses[derivationIndex] {
            case .none,
                 .undefined?:
                // Ring status not delivered yet — defer rather than guess.
                return
            case .defined(.none)?:
                // The ring status was delivered empty (ring retracted): fall back to onboarding.
                resolved[derivationIndex] = .onboarding
            case let .defined(.some(status))?:
                guard status.includesKey(from: position) else { return }
                resolved[derivationIndex] = .inRecycler(
                    Voucher.Recycler(index: ringIndex, membersCount: status.included)
                )
            }
        }
    }
}

// MARK: - Persistence

private extension VoucherLocationService {
    func writeLocations(_ locations: [DerivationIndex: Voucher.OnChainState]) async throws {
        logger.debug(locations.toDebugDescription)

        guard !locations.isEmpty else { return }

        // A dedicated write-only mapper touches only remoteState, so a concurrent change to any other
        // voucher field is not clobbered by this location write.
        let updates = locations.map {
            VoucherLocationUpdate(derivationIndex: $0.key, remoteState: $0.value)
        }
        try await databaseFactory.makeVoucherLocationRepository()
            .saveOperation({ updates }, { [] })
            .asyncExecute()
        logger.debug("Updated \(updates.count) voucher locations via subscription")
    }
}
