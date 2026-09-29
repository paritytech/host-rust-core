package io.paritytech.polkadotapp.feature_become_citizen_api.data.model

import io.paritytech.polkadotapp.common.domain.model.AccountId
import kotlinx.serialization.Serializable

@Serializable
class ProofOfInkPerson(
    // List of candidates that have claimed person's ticket and are currently going through verification process
    val activeReferrals: List<AccountId>,
    // Whether this person has been banned from participating in referral system. Banned users cannot issue referral tickets
    val banned: Boolean,
    // Number of vouchers a person can claim. This is incremented once one of active referrals fully pass the verification
    val pendingReferralRewards: Int,
    // Maximum number of unclaimed tickets this person might have
    val allowedReferralTickets: Int,
)
