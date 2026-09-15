import AsyncExtensions
import Coinage
import Foundation

/// Streams the lifecycle of a single W3S payment by observing its persisted record.
///
/// The record is the single source of truth: ``W3sPaymentTrackingService`` advances
/// the persisted status while this reporter only projects it into ``ClaimStatus``
/// for the transfer screen. `start(with:)` is a no-op — tracking is driven by the
/// app-level service, not by the screen.
final class W3sPaymentLifecycleReporter: TransferLifecycleReporting {
    private let historyStore: W3sPaymentHistoryStoring
    private let paymentId: String

    init(historyStore: W3sPaymentHistoryStoring, paymentId: String) {
        self.historyStore = historyStore
        self.paymentId = paymentId
    }

    func makeStream() -> AnyAsyncSequence<ClaimStatus> {
        let source = historyStore.observeRecord(paymentId: paymentId)

        return AsyncStream<ClaimStatus> { continuation in
            let task = Task {
                var lastStatus: ClaimStatus?
                do {
                    for try await record in source {
                        guard let status = record?.claimStatus, status != lastStatus else {
                            continue
                        }
                        lastStatus = status
                        continuation.yield(status)
                        if status.isTerminal {
                            break
                        }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyAsyncSequence()
    }

    func start(with _: TransferTrackingContext) {}
}

private extension W3sPaymentRecord {
    var claimStatus: ClaimStatus {
        switch status {
        case .pending,
             .submitted:
            .detecting
        case .sent:
            .sent
        case .claimed:
            .finished(claimedAmount: memo.totalValue)
        case .failed,
             .revoked:
            .error
        }
    }
}
