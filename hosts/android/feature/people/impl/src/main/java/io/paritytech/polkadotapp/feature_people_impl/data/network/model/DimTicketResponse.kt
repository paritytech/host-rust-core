package io.paritytech.polkadotapp.feature_people_impl.data.network.model

internal data class DimTicketResponse(
    val inviter: String,
    val publicKey: String,
    val signature: String,
)
