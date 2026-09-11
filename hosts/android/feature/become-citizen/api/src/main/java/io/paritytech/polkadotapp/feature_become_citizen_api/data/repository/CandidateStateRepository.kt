package io.paritytech.polkadotapp.feature_become_citizen_api.data.repository

import io.paritytech.polkadotapp.chains.di.LocalSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.candidates
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.people
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.ProofOfInkPerson
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

interface CandidateStateRepository {
    fun personFlow(chainId: ChainId, personId: PersonId): Flow<ProofOfInkPerson?>

    fun proofOfInkCandidateFlow(accountId: AccountId, chainId: ChainId): Flow<ProofOfInkCandidate?>

    suspend fun getProofOfInkCandidate(accountId: AccountId, chainId: ChainId): ProofOfInkCandidate?
}

class RealCandidateStateRepository @Inject constructor(
    @LocalSourceQualifier private val localStorageDataSource: StorageDataSource
) : CandidateStateRepository {
    override fun personFlow(chainId: ChainId, personId: PersonId): Flow<ProofOfInkPerson?> {
        return localStorageDataSource.subscribe(chainId) {
            metadata.proofOfInk.people.observe(personId)
        }
    }

    override fun proofOfInkCandidateFlow(accountId: AccountId, chainId: ChainId): Flow<ProofOfInkCandidate?> {
        return localStorageDataSource.subscribe(chainId) {
            metadata.proofOfInk.candidates.observe(accountId.value)
        }
    }

    override suspend fun getProofOfInkCandidate(accountId: AccountId, chainId: ChainId): ProofOfInkCandidate? {
        return localStorageDataSource.query(chainId) {
            metadata.proofOfInk.candidates.query(accountId.value)
        }
    }
}
