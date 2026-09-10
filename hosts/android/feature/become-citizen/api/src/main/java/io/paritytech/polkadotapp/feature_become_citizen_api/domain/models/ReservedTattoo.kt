package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooCommitmentExpiration

class ReservedTattoo(
    val id: TattooId,
    val familyId: ByteArray,
    val familyMetadata: TattooFamilyMetadata,
    val reservationState: ReservationState,
) {
    sealed class ReservationState {
        class WaitingForEvidence(val expiration: TattooCommitmentExpiration) : ReservationState()

        data object EvidenceProvided : ReservationState()

        data object Invalid : ReservationState()
    }
}
