package io.paritytech.polkadotapp.feature_become_citizen_impl.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.multiNetwork.withRuntime
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.maxActiveReferrals
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.referralTickets
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.ProofOfInkReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.ProofOfInkReferralsRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketOrigin
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage.ReferralTicketsStorage
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class RealProofOfInkReferralsRepository(
    private val localStorageDataSource: StorageDataSource,
    private val referralTicketsStorage: ReferralTicketsStorage,
    private val chainRegistry: ChainRegistry
) : ProofOfInkReferralsRepository {
    override fun referralTicketsFlow(chainId: ChainId, personId: PersonId): Flow<List<ProofOfInkReferralTicket>> {
        return localStorageDataSource.subscribe(chainId) {
            metadata.proofOfInk.referralTickets.observe(personId)
                .map { it.orEmpty() }
        }
    }

    override suspend fun saveTicket(origin: ReferralTicketOrigin, referralTicket: ReferralTicket) {
        referralTicketsStorage.saveTicket(origin, referralTicket)
    }

    override fun removeTicket(origin: ReferralTicketOrigin) {
        referralTicketsStorage.removeSavedTicket(origin)
    }

    override suspend fun hasSavedTicket(origin: ReferralTicketOrigin): Boolean {
        return referralTicketsStorage.hasSavedTicket(origin)
    }

    override suspend fun getSavedTicket(origin: ReferralTicketOrigin): Result<ReferralTicket?> {
        return runCatching {
            referralTicketsStorage.getSavedTicket(origin)
        }
    }

    override fun subscribeSavedTicket(origin: ReferralTicketOrigin): Flow<ReferralTicket?> {
        return referralTicketsStorage.subscribeSavedTicket(origin)
    }

    override suspend fun getMaxActiveReferrals(chainId: ChainId): Result<Int> {
        return runCatching {
            chainRegistry.withRuntime(chainId) {
                runtime.metadata.proofOfInk.maxActiveReferrals
            }
        }
    }
}
