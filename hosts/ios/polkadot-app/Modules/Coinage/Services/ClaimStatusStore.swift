import AsyncExtensions
import Coinage
import Foundation

/// In-memory store for claim/send operation statuses, backed by ``AsyncCurrentValueSubject``.
///
/// Provides observable streams per message ID so chat extensions can react to status changes
/// in real-time. Statuses are derived live by ``CoinageTransferMonitor`` from the durability layer
/// (`groupId = messageId`) — nothing is persisted here.
actor ClaimStatusStore: ClaimStatusPublishing {
    private var statuses: [String: ClaimStatus] = [:]
    private var subjects: [String: AsyncCurrentValueSubject<ClaimStatus>] = [:]

    func updateStatus(_ status: ClaimStatus, forMessageId messageId: String) {
        statuses[messageId] = status

        if let subject = subjects[messageId] {
            subject.send(status)
        }

        guard status.isTerminal else { return }

        subjects[messageId]?.send(Termination<Never>.finished)
        subjects[messageId] = nil
    }

    func status(forMessageId messageId: String) -> ClaimStatus? {
        statuses[messageId]
    }

    /// Returns a stream that immediately yields the current status (if any),
    /// then yields future updates. Finishes automatically on terminal statuses.
    func watchStatus(forMessageId messageId: String) -> AnyAsyncSequence<ClaimStatus> {
        if let subject = subjects[messageId] {
            return subject.eraseToAnyAsyncSequence()
        }

        guard let current = statuses[messageId] else {
            let subject = AsyncCurrentValueSubject<ClaimStatus>(.detecting)
            subjects[messageId] = subject
            return subject.eraseToAnyAsyncSequence()
        }

        // Terminal status - emit current value and finish
        guard !current.isTerminal else {
            let subject = AsyncJustSequence<ClaimStatus>(current)
            return subject.eraseToAnyAsyncSequence()
        }

        let subject = AsyncCurrentValueSubject<ClaimStatus>(current)
        subjects[messageId] = subject
        return subject.eraseToAnyAsyncSequence()
    }
}

extension ClaimStatus {
    var isTerminal: Bool {
        switch self {
        case .finished,
             .error: true
        case .detecting,
             .claiming,
             .partiallyClaimed,
             .sent: false
        }
    }
}
