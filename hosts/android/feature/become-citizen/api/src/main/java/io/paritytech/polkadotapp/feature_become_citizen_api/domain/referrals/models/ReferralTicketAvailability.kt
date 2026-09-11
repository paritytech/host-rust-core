package io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models

import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId

sealed class ReferralTicketAvailability {
    data object NotAvailable : ReferralTicketAvailability()

    data object ActiveReferralsLimitReached : ReferralTicketAvailability()

    class Available(val referrer: PersonId, val existingTicket: ReferralTicket?) : ReferralTicketAvailability()
}
