import Foundation
import SubstrateSdk
import StructuredConcurrency
import SDKLogger

public final class StatementStoreSlotRenewer: StatementStoreSlotRenewing {
    private let chainId: ChainId
    private let slotInfoProvider: StatementStoreSlotInfoProviding
    private let accounting: StatementStoreSlotAccounting
    private let submitter: SlotAssignmentSubmitting
    private let originFactory: AsResourcesOriginCreating
    private let chainTimeProvider: ChainTimeProviding
    private let serialQueue: SerialOperationQueue
    private let logger: SDKLoggerProtocol

    public init(
        chainId: ChainId,
        slotInfoProvider: StatementStoreSlotInfoProviding,
        accounting: StatementStoreSlotAccounting,
        submitter: SlotAssignmentSubmitting,
        originFactory: AsResourcesOriginCreating,
        chainTimeProvider: ChainTimeProviding,
        serialQueue: SerialOperationQueue,
        logger: SDKLoggerProtocol
    ) {
        self.chainId = chainId
        self.slotInfoProvider = slotInfoProvider
        self.accounting = accounting
        self.submitter = submitter
        self.originFactory = originFactory
        self.chainTimeProvider = chainTimeProvider
        self.serialQueue = serialQueue
        self.logger = logger
    }

    public func renew() async throws {
        try await serialQueue.run { [weak self] in
            guard let self else { return }
            let period = try await chainTimeProvider.currentPeriod()
            let plan = try await makeRenewalPlan(period: period)
            logger.info("Allowance renew started for period \(period), found \(plan.pairs.count) items")
            let aborted = try await submitRenewals(plan.pairs, period: period)
            guard !aborted else { return }
            try await deleteOverflow(plan.overflow)
            logger.info("Allowance renew finished for period \(period)")
        }
    }
}

private extension StatementStoreSlotRenewer {
    struct RenewalPlan {
        let pairs: [(allowance: AllowanceRecord, slot: SSSRenewalSlot)]
        let overflow: ArraySlice<AllowanceRecord>
    }

    func makeRenewalPlan(period: UInt32) async throws -> RenewalPlan {
        let slots = try await slotInfoProvider.renewalSlots(period: period)
        let rows = try await accounting.staleRows(currentPeriod: period)
        let sortedRows = rows.sorted { ($0.priority, $0.allocatedAt) > ($1.priority, $1.allocatedAt) }
        let pairs = sortedRows.prefix(slots.count).enumerated().map { index, row in
            (allowance: row, slot: slots[index])
        }
        let overflow = sortedRows.dropFirst(slots.count)
        return RenewalPlan(pairs: pairs, overflow: overflow)
    }

    func submitRenewals(
        _ pairs: [(allowance: AllowanceRecord, slot: SSSRenewalSlot)],
        period: UInt32
    ) async throws -> Bool {
        for (allowance, slot) in pairs {
            let stillCurrent = await (try? chainTimeProvider.currentPeriod()) == period
            guard stillCurrent else {
                logger.debug("Period rollover detected during renewal; aborting remaining submissions")
                return true
            }
            try await submit(allowance: allowance, slot: slot, period: period)
        }
        return false
    }

    func submit(allowance: AllowanceRecord, slot: SSSRenewalSlot, period: UInt32) async throws {
        do {
            let callData = ResourcesPallet.SetStatementStoreAccountCall(
                period: period,
                seq: slot.seq,
                targetAccount: allowance.accountId
            )()
            try await submitter.submit(
                call: callData,
                makeOrigin: { [originFactory, slot] chain in
                    try await originFactory.createSSSOrigin(
                        personOrigin: slot.personOrigin,
                        period: period,
                        seq: slot.seq,
                        chain: chain
                    )
                },
                chainId: chainId
            )
            try await accounting.markRenewed(allowance, period: period, since: Date())
        } catch let SlotSubmissionError.extrinsicFailed(underlying) {
            let stillCurrent = await (try? chainTimeProvider.currentPeriod()) == period
            if stillCurrent {
                logger.error(
                    "On-chain rejection renewing slot for \(allowance.accountId.toHex()): \(underlying); deleting row"
                )
                try await accounting.deleteFor(accountId: allowance.accountId)
            } else {
                logger.warning(
                    "Renewal rejection for \(allowance.accountId.toHex()) coincided with period rollover; leaving stale"
                )
            }
        } catch {
            logger.error("Transient failure renewing slot for \(allowance.accountId.toHex()): \(error); leaving stale")
        }
    }

    func deleteOverflow(_ overflow: ArraySlice<AllowanceRecord>) async throws {
        for row in overflow {
            try await accounting.deleteFor(accountId: row.accountId)
        }
    }
}
