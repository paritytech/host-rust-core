package io.paritytech.polkadotapp.feature_videogame_impl.service

import io.novasama.substrate_sdk_android.extensions.toHexString
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.BinaryScale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.decodeFromByteArray
import io.paritytech.polkadotapp.feature_statement_store_api.domain.CommunicationSession
import io.paritytech.polkadotapp.feature_statement_store_api.domain.models.CommunicationSessionEvent
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.OfferId
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.SignalingEnvelope
import io.paritytech.polkadotapp.tools_media_connection_api.domain.EncodedIceCandidates
import io.paritytech.polkadotapp.tools_media_connection_api.domain.EncodedSdp
import io.paritytech.polkadotapp.tools_media_connection_api.domain.PeerChannelSignaling
import io.paritytech.polkadotapp.tools_media_connection_api.domain.signaling.SignalingMessage
import kotlinx.coroutines.flow.*
import timber.log.Timber
import java.util.UUID

class VideoGamePeerChannelSignaling(
    private val session: CommunicationSession,
    private val gameIndex: GameIndex,
    private val onOfferIdDetermined: suspend (OfferId) -> Unit
) : PeerChannelSignaling {
    private val activeOfferFlow = MutableStateFlow<OfferId?>(null)

    override suspend fun sendOffer(sdp: EncodedSdp) {
        Timber.tag("signal_log").d("sendOffer")
        val offerId = UUID.randomUUID().toString()
        activeOfferFlow.value = offerId

        sendMessage(offerId, SignalingMessage.Offer(sdp))
    }

    override suspend fun sendAnswer(sdp: EncodedSdp) {
        Timber.tag("signal_log").d("sendAnswer")
        sendMessage(awaitOfferId(), SignalingMessage.Answer(sdp))
    }

    override suspend fun sendIceCandidates(candidates: EncodedIceCandidates) {
        Timber.tag("signal_log").d("sendIceCandidates")
        sendMessage(awaitOfferId(), SignalingMessage.IceCandidates(candidates))
    }

    override fun subscribeIncomingIceCandidates(): Flow<EncodedIceCandidates> {
        Timber.tag("signal_log").d("subscribeIncomingIceCandidates")
        return subscribeIceCandidatesEnvelopes()
            .map { it.candidates }
    }

    override suspend fun awaitIncomingAnswer(): EncodedSdp {
        Timber.tag("signal_log").d("awaitIncomingAnswer")
        // if we receive an answer, we must have already sent an offer
        // so the offer ID should be determined, and we can be sure that
        // remote peer received our offer
        onOfferIdDetermined(awaitOfferId())

        return subscribeAnswerEnvelopes()
            .first().sdp
    }

    override suspend fun awaitIncomingOffer(): EncodedSdp {
        Timber.tag("signal_log").d("awaitIncomingOffer")
        val (offerId, offer) = subscribeOfferEnvelopes().first()
        activeOfferFlow.value = offerId
        onOfferIdDetermined(offerId)
        return offer.sdp
    }

    fun reset() {
        Timber.tag("signal_log").d("reset")
        activeOfferFlow.value = null
    }

    fun sendReconnected(offerId: OfferId) {
        Timber.tag("signal_log").d("sendReconnected, offerId: $offerId")
        sendMessage(offerId, SignalingMessage.Reconnected)
    }

    fun subscribeReconnected(): Flow<OfferId> {
        Timber.tag("signal_log").d("subscribeReconnected")
        return subscribeReconnectedEnvelopes()
    }

    private fun sendMessage(offerId: OfferId, message: SignalingMessage) {
        Timber.tag("signal_log").d("sendMessage, offerId: $offerId, message: ${message::class.simpleName}")
        val envelope = SignalingEnvelope(gameIndex, offerId, message)
        val encoded = BinaryScale.encodeToByteArray(SignalingEnvelope.serializer(), envelope)
        session.sendMessage(encoded)
    }

    private fun subscribeOfferEnvelopes(): Flow<Pair<OfferId, SignalingMessage.Offer>> {
        return subscribeMessageEvents()
            .mapNotNull { envelopes ->
                envelopes
                    .lastOrNull { it.message is SignalingMessage.Offer }
                    ?.let { it.offerId to it.message as SignalingMessage.Offer }
            }
            .onEach { (offerId, _) -> Timber.tag("signal_log").d("received offer, offerId: $offerId") }
    }

    private fun subscribeAnswerEnvelopes(): Flow<SignalingMessage.Answer> {
        return subscribeMessageEvents()
            .transform { envelopes ->
                envelopes.forEach { envelope ->
                    if (envelope.offerId == awaitOfferId() && envelope.message is SignalingMessage.Answer) {
                        Timber.tag("signal_log").d("received answer, offerId: ${envelope.offerId}")
                        emit(envelope.message)
                    }
                }
            }
    }

    private fun subscribeReconnectedEnvelopes(): Flow<OfferId> {
        return subscribeMessageEvents()
            .mapNotNull { envelopes ->
                envelopes
                    .lastOrNull { it.message is SignalingMessage.Reconnected }
                    ?.offerId
            }
            .onEach { offerId -> Timber.tag("signal_log").d("received reconnected, offerId: $offerId") }
    }

    private fun subscribeIceCandidatesEnvelopes(): Flow<SignalingMessage.IceCandidates> {
        return subscribeMessageEvents()
            .transform { envelopes ->
                envelopes.forEach { envelope ->
                    if (envelope.offerId == awaitOfferId() && envelope.message is SignalingMessage.IceCandidates) {
                        Timber.tag("signal_log").d("received iceCandidates, offerId: ${envelope.offerId}")
                        emit(envelope.message)
                    }
                }
            }
    }

    private fun subscribeMessageEvents(): Flow<List<SignalingEnvelope>> {
        return session.subscribeEvents()
            .filterIsInstance<CommunicationSessionEvent.NewMessagesReceived>()
            .onEach { event ->
                Timber.tag("signal_log").d("received message event, requestId: ${event.requestId}, messages: ${event.messages.size}")
            }
            .mapNotNull { event ->
                val envelopes = event.messages.mapNotNull { encodedMessage ->
                    runCatching {
                        BinaryScale.decodeFromByteArray<SignalingEnvelope>(encodedMessage)
                    }.onFailure {
                        Timber.w(it, "Failed to decode signaling message: ${encodedMessage.toHexString(withPrefix = true)}")
                    }.getOrNull()
                }.filter { it.gameIndex == gameIndex }

                envelopes.ifEmpty { null }
            }
    }

    private suspend fun awaitOfferId(): OfferId = activeOfferFlow.filterNotNull().first()

    fun getOfferId(): OfferId? {
        Timber.tag("signal_log").d("getOfferId: ${activeOfferFlow.value}")
        return activeOfferFlow.value
    }
}
