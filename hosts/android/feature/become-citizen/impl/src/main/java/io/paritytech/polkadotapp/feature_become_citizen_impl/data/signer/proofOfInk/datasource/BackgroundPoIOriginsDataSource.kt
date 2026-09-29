package io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.datasource

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

class BackgroundPoIOriginsDataSource(
    private val candidateFlow: Flow<ProofOfInkCandidate?>
) : ProofOfInkOriginsDataSource {
    override suspend fun getCandidateState(chainId: ChainId, accountId: AccountId): ProofOfInkCandidate? {
        return candidateFlow.first()
    }
}
