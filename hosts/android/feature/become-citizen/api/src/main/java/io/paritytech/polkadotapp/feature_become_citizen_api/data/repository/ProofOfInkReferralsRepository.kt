package io.paritytech.polkadotapp.feature_become_citizen_api.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.ProofOfInkReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketOrigin
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.coroutines.flow.Flow

interface ProofOfInkReferralsRepository {
    fun referralTicketsFlow(chainId: ChainId, personId: PersonId): Flow<List<ProofOfInkReferralTicket>>

    suspend fun saveTicket(origin: ReferralTicketOrigin, referralTicket: ReferralTicket)

    fun removeTicket(origin: ReferralTicketOrigin)

    suspend fun hasSavedTicket(origin: ReferralTicketOrigin): Boolean

    suspend fun getSavedTicket(origin: ReferralTicketOrigin): Result<ReferralTicket?>

    fun subscribeSavedTicket(origin: ReferralTicketOrigin): Flow<ReferralTicket?>

    suspend fun getMaxActiveReferrals(chainId: ChainId): Result<Int>
}
