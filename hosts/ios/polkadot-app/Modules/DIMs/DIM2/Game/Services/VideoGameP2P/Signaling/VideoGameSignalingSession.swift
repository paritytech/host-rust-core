import Foundation
import SubstrateSdk
import AsyncExtensions
import MessageExchangeKit
import Individuality

/// Implements `PeerConnectionSignaling` for the video game feature.
///
/// Sends and receives `VideoGameSignalingEnvelope` through the MessageExchangeKit
/// peer session infrastructure. Incoming envelopes are filtered by `gameIndex`
/// and `offerId` before being converted to `PeerConnectionSignal`.
actor VideoGameSignalingSession {
    let gameIndex: GamePallet.GameIndex
    let peerAccountId: AccountId
    let sdpCoder: SdpCoding
    let peerLogger: LoggerProtocol
    let signalBatcher: PeerConnectionSignalBatching

    private let exchangeService: AnyMessageExchangeService<OpaqueVideoGameSignalingEnvelope>
    private let peer: MessageExchange.Peer

    /// Buffers WebRTC signaling signals (offer/answer/candidates) so that signals
    /// emitted before the consumer subscribes are not lost.
    /// Replaced with a fresh subject on each reconnection to discard stale signals.
    private var subject = AsyncReplaySubject<PeerConnectionSignal>(
        bufferSize: Constants.signalReplayBufferSize
    )

    private(set) var activeOfferId: String?

    init(
        gameIndex: GamePallet.GameIndex,
        peerAccountId: AccountId,
        exchangeService: AnyMessageExchangeService<OpaqueVideoGameSignalingEnvelope>,
        peer: MessageExchange.Peer,
        sdpCoder: SdpCoding = SdpCoder(),
        signalBatcher: PeerConnectionSignalBatching = PeerConnectionSignalBatcher(),
        peerLogger: LoggerProtocol
    ) {
        self.gameIndex = gameIndex
        self.peerAccountId = peerAccountId
        self.exchangeService = exchangeService
        self.peer = peer
        self.sdpCoder = sdpCoder
        self.signalBatcher = signalBatcher
        self.peerLogger = peerLogger
    }

    deinit {
        peerLogger.debug("Deinit")
    }

    // MARK: - Reconnection

    /// Splits a batch at the latest reconnection request the caller accepts.
    ///
    /// Everything up to and including that request is stale and dropped; the
    /// result carries the accepted offer id and the envelopes that followed it,
    /// which the caller buffers (via `handleIncomingEnvelopes`) after resetting.
    /// Returns `nil` when the batch holds no accepted reconnection.
    func reconnection(
        in envelopes: [VideoGameSignalingEnvelope],
        isValidOffer: (String) -> Bool
    ) -> (offerId: String, following: [VideoGameSignalingEnvelope])? {
        let relevant = envelopes.filter { $0.gameIndex == gameIndex }

        guard let index = relevant.lastIndex(where: {
            $0.message.isReconnected && isValidOffer($0.offerId)
        }) else {
            return nil
        }

        return (relevant[index].offerId, Array(relevant[(index + 1)...]))
    }

    /// Prepares the session for a fresh connection attempt by clearing the active
    /// offer ID and replacing the signal subject so stale signals from the
    /// previous connection are not replayed to new subscribers.
    func resetForReconnection() {
        activeOfferId = nil
        subject = AsyncReplaySubject<PeerConnectionSignal>(
            bufferSize: Constants.signalReplayBufferSize
        )
    }

    // MARK: - Sending

    func sendReconnected(_ offerId: String) {
        sendEnvelopes([(offerId: offerId, message: .reconnected)])
    }

    // MARK: - Receiving (called by delegate/coordinator)

    /// Buffers the offer/answer/candidate signals from a batch of envelopes.
    /// `reconnected` envelopes are handled by the consumer via
    /// `reconnection(in:isValidOffer:)`, so they are ignored here.
    func handleIncomingEnvelopes(_ envelopes: [VideoGameSignalingEnvelope]) {
        let currentSubject = subject
        let pendingSignals = parseSignals(envelopes)

        for signal in pendingSignals {
            currentSubject.send(signal)
        }
    }
}

// MARK: - PeerConnectionSignaling

extension VideoGameSignalingSession: PeerConnectionSignaling {
    var signals: AnyAsyncSequence<PeerConnectionSignal> {
        get async {
            subject.eraseToAnyAsyncSequence()
        }
    }

    @discardableResult
    func send(
        _ signals: [PeerConnectionSignal]
    ) async throws -> PeerConnectionSignalSendResult {
        let batches = signalBatcher.batch(signals)
        let encoded = batches.compactMap { encodeSignal($0) }
        sendEnvelopes(encoded)
        return batches.count == encoded.count ? .fullySent : .notFullySent
    }
}

// MARK: - Private

private extension VideoGameSignalingSession {
    enum Constants {
        static let signalReplayBufferSize: UInt = 100
    }

    typealias EncodedSignal = (offerId: String, message: VideoGameSignalingMessage)

    /// `.candidates` preserves the candidate batch so a flush can send recently
    /// gathered ICE candidates with a single signaling envelope.
    func encodeSignal(_ signal: BatchedPeerConnectionSignal) -> EncodedSignal? {
        do {
            switch signal {
            case let .offer(setup):
                let offerId = UUID().uuidString
                let encoded = try sdpCoder.encodeSetup(setup)
                activeOfferId = offerId
                return (offerId, .offer(encoded))

            case let .answer(setup):
                guard let offerId = activeOfferId else {
                    peerLogger.error("Cannot send answer without active offer ID")
                    return nil
                }

                let encoded = try sdpCoder.encodeSetup(setup)
                return (offerId, .answer(encoded))

            case let .candidates(candidates):
                guard let offerId = activeOfferId else {
                    peerLogger.error("Cannot send candidates without active offer ID")
                    return nil
                }

                guard !candidates.isEmpty else {
                    peerLogger.error("No candidates to send")
                    return nil
                }

                let encoded = try sdpCoder.encodeCandidates(candidates)
                return (offerId, .iceCandidates(encoded))

            case .closed:
                peerLogger.debug("Video game signaling does not propagate closed signal")
                return nil
            }
        } catch {
            peerLogger.error("Signal encoding failed: \(error)")
            return nil
        }
    }

    func sendEnvelopes(_ encoded: [EncodedSignal]) {
        guard !encoded.isEmpty else {
            return
        }

        let envelopes = encoded.map { entry in
            OpaqueMessageWrapper(message: VideoGameSignalingEnvelope(
                gameIndex: gameIndex,
                offerId: entry.offerId,
                message: entry.message
            ))
        }

        exchangeService.addMessagesToQueue(envelopes, for: peer)
    }

    /// When multiple offers accumulate in a single batch, only the latest is
    /// used; earlier ones are stale and get discarded.
    func parseSignals(
        _ envelopes: [VideoGameSignalingEnvelope]
    ) -> [PeerConnectionSignal] {
        let relevant = envelopes.filter { $0.gameIndex == gameIndex }
        let deduplicated = dropStaleEnvelopes(relevant)

        var signals: [PeerConnectionSignal] = []

        for envelope in deduplicated {
            appendSignal(from: envelope, into: &signals)
        }

        return signals
    }

    /// Keeps only the latest offer and drops earlier offer duplicates.
    /// Reconnected-event deduplication is kept for defensive parsing only; the
    /// context handles accepted reconnection requests before this point.
    func dropStaleEnvelopes(
        _ envelopes: [VideoGameSignalingEnvelope]
    ) -> [VideoGameSignalingEnvelope] {
        var latestOfferIndex: Int?
        var latestReconnectedIndex: Int?

        for (index, envelope) in envelopes.enumerated() {
            if envelope.message.isOffer {
                latestOfferIndex = index
            } else if envelope.message.isReconnected {
                latestReconnectedIndex = index
            }
        }

        return envelopes
            .enumerated()
            .filter { index, envelope in
                if envelope.message.isOffer {
                    return index == latestOfferIndex
                }
                if envelope.message.isReconnected {
                    return index == latestReconnectedIndex
                }
                return true
            }
            .map(\.element)
    }

    /// `reconnected` envelopes are handled by the consumer via
    /// `reconnection(in:isValidOffer:)`, so they are skipped here.
    func appendSignal(
        from envelope: VideoGameSignalingEnvelope,
        into signals: inout [PeerConnectionSignal]
    ) {
        switch envelope.message {
        case .reconnected:
            break

        case let .offer(sdpData):
            handleOffer(sdpData, offerId: envelope.offerId, signals: &signals)

        case let .answer(sdpData):
            handleAnswer(sdpData, offerId: envelope.offerId, signals: &signals)

        case let .iceCandidates(candidatesData):
            handleCandidates(candidatesData, offerId: envelope.offerId, signals: &signals)
        }
    }

    func handleOffer(_ sdpData: Data, offerId: String, signals: inout [PeerConnectionSignal]) {
        do {
            let setup = try sdpCoder.decodeSetup(sdpData)
            activeOfferId = offerId

            signals.append(.offer(setup.setupSdp))

            if !setup.candidates.isEmpty {
                signals.append(.candidates(setup.candidates))
            }

            peerLogger.debug("Received offer with ID: \(offerId)")
        } catch {
            peerLogger.error("Failed to decode offer SDP: \(error)")
        }
    }

    func handleAnswer(_ sdpData: Data, offerId: String, signals: inout [PeerConnectionSignal]) {
        guard offerId == activeOfferId else {
            peerLogger.debug("Ignoring answer with mismatched offer ID: \(offerId)")
            return
        }

        do {
            let setup = try sdpCoder.decodeSetup(sdpData)
            signals.append(.answer(setup.setupSdp))

            if !setup.candidates.isEmpty {
                signals.append(.candidates(setup.candidates))
            }

            peerLogger.debug("Received answer for offer: \(offerId)")
        } catch {
            peerLogger.error("Failed to decode answer SDP: \(error)")
        }
    }

    func handleCandidates(_ data: Data, offerId: String, signals: inout [PeerConnectionSignal]) {
        guard offerId == activeOfferId else {
            peerLogger.debug("Ignoring candidates with mismatched offer ID: \(offerId)")
            return
        }

        do {
            let candidates = try sdpCoder.decodeCandidates(data)
            signals.append(.candidates(candidates))

            peerLogger.debug("Received \(candidates.count) ICE candidates")
        } catch {
            peerLogger.error("Failed to decode ICE candidates: \(error)")
        }
    }
}
