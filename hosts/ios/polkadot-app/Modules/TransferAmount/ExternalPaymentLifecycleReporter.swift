import AsyncExtensions
import Coinage
import Foundation
@preconcurrency import SDKLogger

/// Projects the coinage external-payment status stream into ``ClaimStatus``
/// for the transfer screen. Tracking runs in an owned task so submission
/// returns immediately and the screen reacts to streamed statuses.
final class ExternalPaymentLifecycleReporter: TransferLifecycleReporting {
    private let coinageService: CoinageServicing
    private let logger: SDKLoggerProtocol?
    private let subject = AsyncCurrentValueSubject<ClaimStatus>(.detecting)

    init(
        coinageService: CoinageServicing,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.coinageService = coinageService
        self.logger = logger
    }

    func makeStream() -> AnyAsyncSequence<ClaimStatus> {
        subject.eraseToAnyAsyncSequence()
    }

    func start(with context: TransferTrackingContext) {
        guard case let .externalPayment(paymentId, amountInPlanks) = context else {
            subject.send(Termination<Never>.finished)
            return
        }

        Task { [coinageService, subject, logger] in
            do {
                let statuses = try await coinageService.subscribeExternalPaymentStatus(
                    paymentId: paymentId
                )

                for try await status in statuses {
                    switch status {
                    case .processing:
                        subject.send(.detecting)
                    case .completed:
                        subject.send(.finished(claimedAmount: amountInPlanks))
                        subject.send(Termination<Never>.finished)
                        return
                    case let .failed(reason):
                        logger?.error("External payment \(paymentId) failed: \(reason)")
                        subject.send(.error)
                        subject.send(Termination<Never>.finished)
                        return
                    }
                }

                subject.send(Termination<Never>.finished)
            } catch {
                logger?.error("External payment \(paymentId) status stream failed: \(error)")
                subject.send(.error)
                subject.send(Termination<Never>.finished)
            }
        }
    }
}
