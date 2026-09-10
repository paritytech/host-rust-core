import Foundation
import Foundation_iOS
import MessageExchangeKit
import StatementStore
import Individuality

protocol VideoGamePeerSessionDelegating: PeerSessionDelegate, TypeErasedDelegateStoring
    where Message == OpaqueVideoGameSignalingEnvelope {
    var incomingEnvelopes: AsyncStream<[VideoGameSignalingEnvelope]> { get }
    func finishIncomingEnvelopes()
}

final class VideoGamePeerSessionDelegate: VideoGamePeerSessionDelegating {
    typealias Message = OpaqueVideoGameSignalingEnvelope

    private let peerLogger: LoggerProtocol
    private let incomingEnvelopesContinuation: AsyncStream<[VideoGameSignalingEnvelope]>.Continuation

    let incomingEnvelopes: AsyncStream<[VideoGameSignalingEnvelope]>

    init(peerLogger: LoggerProtocol) {
        self.peerLogger = peerLogger
        (incomingEnvelopes, incomingEnvelopesContinuation) = AsyncStream.makeStream()
    }

    deinit {
        peerLogger.debug("Deinit")
        finishIncomingEnvelopes()
    }

    func finishIncomingEnvelopes() {
        incomingEnvelopesContinuation.finish()
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didUpdateState state: PeerSessionState
    ) {
        peerLogger.debug("Peer session state: \(state)")
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didInitializeWithOutgoingMessages messages: [OpaqueVideoGameSignalingEnvelope]
    ) {
        peerLogger.debug("Peer session initialized with \(messages.count) pending messages")
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldResetAfter error: MessageExchange.InitializationError
    ) -> Bool {
        peerLogger.debug("Session going to reset after \(error)")
        return true
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didFinishAddingMessageToQueue _: OpaqueVideoGameSignalingEnvelope,
        withError error: MessageExchange.AddToQueueError?
    ) {
        peerLogger.debug("Did add envelope to queue")

        if let error {
            peerLogger.error("Did add envelope to queue error: \(error)")
        }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didPostMessages messages: [OpaqueVideoGameSignalingEnvelope],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        peerLogger.debug("Did post \(messages.count) envelopes")

        if let error {
            peerLogger.error("Did post \(messages.count) envelopes error: \(error)")
        }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didDeliverMessages messages: [OpaqueVideoGameSignalingEnvelope],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        peerLogger.debug("Did deliver \(messages.count) envelopes")

        if let error {
            peerLogger.error("Did deliver \(messages.count) envelopes error: \(error)")
        }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didReceiveMessages messages: [OpaqueVideoGameSignalingEnvelope],
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        peerLogger.debug("Did receive \(messages.count) envelopes")
        incomingEnvelopesContinuation.yield(messages.map(\.message))
        respondHandler(.success)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didCompactMessages _: OpaqueVideoGameSignalingEnvelope,
        originalMessages _: [OpaqueVideoGameSignalingEnvelope]
    ) {}

    func peerSessionDidReceiveMessagesError(
        _: any PeerSessionProtocol,
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        peerLogger.error("Did receive envelope error")
        respondHandler(.success)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldIgnoreStatementAfter _: MessageExchange.IncomingMessageError
    ) -> Bool {
        peerLogger.debug("Ignoring statement")
        return true
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldReinitializeAfterSubmitError error: Error
    ) -> Bool {
        peerLogger.debug("Submit error: \(error)")

        if case StatementSubmitError.rejected(.channelPriorityTooLow) = error {
            return false
        }

        return true
    }
}
