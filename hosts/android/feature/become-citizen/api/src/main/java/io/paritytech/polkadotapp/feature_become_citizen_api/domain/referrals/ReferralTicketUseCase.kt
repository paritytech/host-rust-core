package io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketAvailability
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketDeeplink
import kotlinx.coroutines.flow.Flow

interface ReferralTicketUseCase {
    fun referralTicketAvailabilityFlow(): Flow<ReferralTicketAvailability>

    suspend fun generateReferralTicket(availability: ReferralTicketAvailability.Available): Result<ReferralTicketDeeplink>
}
