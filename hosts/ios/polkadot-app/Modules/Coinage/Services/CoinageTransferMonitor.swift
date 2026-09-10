import BigInt
import Coinage
import CommonService
import Foundation
import Operation_iOS
import SubstrateSdk

/// Monitors coinage transfer lifecycle for both directions, driven entirely off the durability layer
/// keyed by `groupId = messageId` — no bespoke claim-status persistence:
/// - Incoming: claims transferred coins (with retry) via ``ClaimCoinsServicing``.
/// - Outgoing: derives Appendix-A payment status via ``CoinageTransferStatusServicing``.
protocol CoinageTransferMonitoring: AsyncApplicationServicing {}

final class CoinageTransferMonitor {
    private let coinageService: any CoinageServicing
    private let messageProviderFactory: ChatMessageDataProviderMaking
    private let claimStatusStore: ClaimStatusStore
    private let logger: LoggerProtocol

    /// Top-level tasks that listen to the CoreData message streams.
    private var incomingTransfersSubscription: Task<Void, Never>?
    private var outgoingTransfersSubscription: Task<Void, Never>?

    /// Per-message tasks keyed by messageId. Each resolves independently, avoiding head-of-line
    /// blocking across messages.
    private let taskRegistry = ActiveTaskRegistry()

    init(
        coinageService: any CoinageServicing,
        storageFacade: StorageFacadeProtocol,
        claimStatusStore: ClaimStatusStore,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.coinageService = coinageService
        self.claimStatusStore = claimStatusStore
        self.logger = logger

        let repositoryFactory = ChatMessageRepositoryFactory(storageFacade: storageFacade)
        messageProviderFactory = ChatMessageDataProviderFactory(
            repositoryFactory: repositoryFactory,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension CoinageTransferMonitor: CoinageTransferMonitoring {
    func setup() async {
        subscribeIncomingMessages()
        subscribeOutgoingMessages()
    }

    func throttle() async {
        incomingTransfersSubscription?.cancel()
        outgoingTransfersSubscription?.cancel()
        await taskRegistry.cancelAll()
    }
}

// MARK: - Incoming (claim)

private extension CoinageTransferMonitor {
    func subscribeIncomingMessages() {
        logger.debug("Going to subscribe to incoming messages")

        incomingTransfersSubscription = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = messageProviderFactory.subscribeMessages(with: .incomingCoinageSendMessages())
                for try await messages in stream {
                    try Task.checkCancellation()

                    logger.debug("Found \(messages.count) incoming coinage messages")

                    for message in messages {
                        await startIncoming(for: message)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Coinage claim subscription failed: \(error)")
            }
        }
    }

    func startIncoming(for message: Chat.LocalMessage) async {
        guard case let .coinageSend(content) = message.content else { return }
        let messageId = message.messageId
        guard await taskRegistry.contains(messageId) == false else { return }

        let memo = content.transferMemo
        let task = Task { [coinageService, claimStatusStore, taskRegistry, logger] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await coinageService.denominationContext()
                let retryUntil = Date().addingTimeInterval(CoinageConstants.claimRetryWindow)

                logger.debug("Starting processing incoming coinage message=\(messageId)")

                let detections = coinageService.claimCoinsService.claim(
                    coinKeys: memo.entries,
                    groupId: messageId,
                    retryUntil: retryUntil,
                    context: context
                )
                for try await detection in detections {
                    await claimStatusStore.updateStatus(detection.incomingStatus, forMessageId: messageId)
                }
            } catch {
                logger.error("Failed to claim coinage for \(messageId): \(error)")
                await claimStatusStore.updateStatus(.error, forMessageId: messageId)
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }
}

// MARK: - Outgoing (payment status)

private extension CoinageTransferMonitor {
    func subscribeOutgoingMessages() {
        logger.debug("Going to subscribe to outgoing messages")

        outgoingTransfersSubscription = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = messageProviderFactory.subscribeMessages(with: .outgoingLocalDeviceCoinageSendMessages())
                for try await messages in stream {
                    try Task.checkCancellation()
                    for message in messages {
                        await startOutgoing(for: message)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Coinage send subscription failed: \(error)")
            }
        }
    }

    func startOutgoing(for message: Chat.LocalMessage) async {
        guard case let .coinageSend(content) = message.content else { return }
        let messageId = message.messageId
        guard await taskRegistry.contains(messageId) == false else { return }

        let memo = content.transferMemo
        let task = Task { [coinageService, claimStatusStore, taskRegistry, logger] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await coinageService.denominationContext()
                let statuses = coinageService.transferStatusService.subscribeStatuses(coinKeys: memo.entries)

                logger.debug("Processing transfer for message: \(messageId) entries=\(memo.entries.count)")

                for try await states in statuses {
                    logger.debug("Got statuses for messageId=\(messageId) states=\(states.count)")

                    let proposedStatus = states.outgoingStatus(context: context)

                    logger.debug("Status=\(proposedStatus) message=\(messageId)")

                    await claimStatusStore.updateStatus(
                        proposedStatus,
                        forMessageId: messageId
                    )
                    if !states.isEmpty, states.values.allSatisfy(\.status.isTerminal) { break }
                }
            } catch {
                logger.error("Send status monitoring failed for \(messageId): \(error)")
                await claimStatusStore.updateStatus(.error, forMessageId: messageId)
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }
}

// MARK: - Status mapping

private extension CoinageTransferDetection {
    /// Maps the received-claim detection onto the chat status. Partial claims surface via
    /// `finished(claimedAmount:)` — the extension renders the shortfall against the message total.
    var incomingStatus: ClaimStatus {
        switch self {
        case .detecting:
            .detecting
        case .claiming:
            .claiming
        case let .claimingRest(claimed):
            .partiallyClaimed(claimed: claimed)
        case let .claimed(amount, _):
            .finished(claimedAmount: amount)
        case let .claimedPartially(claimed):
            .finished(claimedAmount: claimed)
        case .notClaimed:
            .error
        }
    }
}

private extension [PublicKey: CoinageTransferState] {
    /// Aggregates per-coin Appendix-A statuses into one message-level status. Mirrors Android's
    /// `toPaymentStatus`: any coin still to be taken keeps the message at `sent`/`detecting`; once
    /// nothing is outstanding, the claimed value is final.
    func outgoingStatus(context: DenominationBreakdownContext) -> ClaimStatus {
        let states = Array(values)
        guard !states.isEmpty else { return .detecting }

        let claimed = states.filter { if case .claimed = $0.status { true } else { false } }
        let awaiting = states.filter { $0.status == .awaitingClaim }
        let outstanding = states.filter { $0.status == .awaitingClaim || $0.status == .detecting }

        if !outstanding.isEmpty {
            return awaiting.isEmpty && claimed.isEmpty ? .detecting : .sent
        }
        guard !claimed.isEmpty else { return .error }

        let amount = claimed.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.coin.exponent) }
        return .finished(claimedAmount: amount)
    }
}

private extension Chat.LocalMessage.Content.Transfer {
    var transferMemo: TransferMemo {
        TransferMemo(entries: coinKeys, totalValue: totalValue)
    }
}

// MARK: - Active Task Registry

private actor ActiveTaskRegistry {
    private var tasks: [String: Task<Void, Never>] = [:]

    func register(_ task: Task<Void, Never>, forMessageId id: String) {
        tasks[id] = task
    }

    func remove(forMessageId id: String) {
        tasks.removeValue(forKey: id)
    }

    func contains(_ id: String) -> Bool {
        tasks[id] != nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
