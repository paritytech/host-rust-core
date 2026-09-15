import Coinage
import Foundation
import SubstrateSdk
import UIKitExt

/// Chat extension that observes coinage claim/send status and updates message content in real-time.
///
/// Watches ``ClaimStatusStore`` for status changes on both incoming (claim) and outgoing (send)
/// coinage messages, overriding message content via ``ChatExtensionProcessingContextProtocol/modifyMessageContent``
/// to reflect the current operation status (processing/finished/error).
final class CoinageTransferExtension: ChatExtending, @unchecked Sendable {
    let identifier: ChatExtension.Id = "CoinageClaim"

    private let claimStatusStore: ClaimStatusStore
    private let lock = NSLock()
    private var activeTasks: [Chat.MessageId: Task<Void, Never>] = [:]

    init(claimStatusStore: ClaimStatusStore) {
        self.claimStatusStore = claimStatusStore
    }

    deinit {
        lock.lock()
        let tasks = activeTasks.values
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    func activeIn(chat: Chat.Id) -> Bool {
        switch chat {
        case .person:
            true
        case .chatExtension:
            false
        }
    }

    func attach(presentationView _: ControllerBackedProtocol) {}

    func process(
        message: Chat.LocalMessage,
        lastProcessingOutcome _: ChatExtension.ProcessingHistoryOutcome,
        context: ChatExtensionProcessingContextProtocol
    ) async -> ChatExtension.ProcessingResult {
        guard case let .coinageSend(content) = message.content else {
            return .skipped
        }

        let messageId = message.messageId
        let totalValue = content.totalValue
        let coinKeys = content.coinKeys
        let store = claimStatusStore
        let isIncoming = message.status.isIncoming

        startWatching(
            messageId: messageId,
            totalValue: totalValue,
            coinKeys: coinKeys,
            isIncoming: isIncoming,
            store: store,
            context: context
        )

        return .processed
    }

    func process(action _: Chat.Action, context _: ChatExtensionActionContextProtocol) async {}

    private nonisolated func startWatching(
        messageId: Chat.MessageId,
        totalValue: Balance,
        coinKeys: [Data],
        isIncoming: Bool,
        store: ClaimStatusStore,
        context: ChatExtensionProcessingContextProtocol
    ) {
        lock.lock()
        activeTasks[messageId]?.cancel()

        let task = Task {
            do {
                for try await newStatus in await store.watchStatus(forMessageId: messageId) {
                    guard !Task.isCancelled else { break }

                    let displayValue: Balance
                    let transferStatus: Chat.LocalMessage.Content.Transfer.Status
                    let originalTotal: Balance?

                    switch newStatus {
                    case .detecting:
                        displayValue = totalValue
                        transferStatus = .processing
                        originalTotal = nil
                    case .claiming:
                        displayValue = totalValue
                        transferStatus = isIncoming ? .claiming : .processing
                        originalTotal = nil
                    case let .partiallyClaimed(claimed):
                        // Show what has arrived so far under a "partially claimed" subtitle — no
                        // strikethrough (that path is reserved for the final shortfall).
                        displayValue = claimed
                        transferStatus = isIncoming ? .partiallyClaimed : .sent
                        originalTotal = nil
                    case .sent:
                        displayValue = totalValue
                        transferStatus = isIncoming ? .processing : .sent
                        originalTotal = nil
                    case let .finished(claimedAmount) where claimedAmount != totalValue:
                        displayValue = claimedAmount
                        transferStatus = .finished
                        originalTotal = totalValue
                    case let .finished(claimedAmount):
                        displayValue = claimedAmount
                        transferStatus = .finished
                        originalTotal = nil
                    case .error:
                        displayValue = totalValue
                        transferStatus = .error
                        originalTotal = nil
                    }

                    let override = Chat.LocalMessage.Content.Transfer(
                        totalValue: displayValue,
                        coinKeys: coinKeys,
                        status: transferStatus,
                        originalTotalValue: originalTotal
                    )
                    try? await context.modifyMessageContent(
                        messageId: messageId,
                        content: .coinageSend(override)
                    )
                }
            } catch {}

            self.removeTask(for: messageId)
        }

        activeTasks[messageId] = task
        lock.unlock()
    }

    private nonisolated func removeTask(for messageId: Chat.MessageId) {
        lock.lock()
        activeTasks[messageId] = nil
        lock.unlock()
    }
}
