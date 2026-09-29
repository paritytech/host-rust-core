package io.paritytech.polkadotapp.feature_become_citizen_api.data.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.ByteArraySerializable
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketPublic
import kotlinx.serialization.Serializable

@Serializable
class ProofOfInkReferralTicket(val ticket: ByteArraySerializable)

fun ProofOfInkReferralTicket.toDomain(): ReferralTicketPublic {
    return ReferralTicketPublic(ticket)
}
