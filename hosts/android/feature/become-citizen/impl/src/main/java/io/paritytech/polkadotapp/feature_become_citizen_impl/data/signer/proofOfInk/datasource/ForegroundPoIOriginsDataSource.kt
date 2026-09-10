package io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.datasource

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.CandidateStateRepository
import javax.inject.Inject

class ForegroundPoIOriginsDataSource @Inject constructor(
    private val proofOfInkRepository: CandidateStateRepository,
) : ProofOfInkOriginsDataSource {
    override suspend fun getCandidateState(chainId: ChainId, accountId: AccountId): ProofOfInkCandidate? {
        return proofOfInkRepository.getProofOfInkCandidate(accountId, chainId)
    }
}
