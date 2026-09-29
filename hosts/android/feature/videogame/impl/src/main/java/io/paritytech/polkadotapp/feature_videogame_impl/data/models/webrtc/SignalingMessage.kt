package io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.tools_media_connection_api.domain.signaling.SignalingMessage
import kotlinx.serialization.Serializable

typealias OfferId = String

@Serializable
class SignalingEnvelope(
    val gameIndex: GameIndex,
    val offerId: OfferId,
    val message: SignalingMessage
)
