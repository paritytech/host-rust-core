package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.feature_videogame_impl.data.AttestationNftHash
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import javax.inject.Inject

/**
 * Live top-up for attestation NFTs that mint after the one-shot read at results time.
 * Observes the candidate (owner, hash) keys and emits each candidate hash the moment it
 * appears on chain, exactly once, in candidate order.
 */
class GameNftsSubscriptionService @Inject constructor(
    private val repository: VideoGameRepositoryInternal
) {
    fun newlyMintedHashes(
        chainId: ChainId,
        owner: OnChainAccountOrPerson,
        candidateHashes: List<AttestationNftHash>
    ): Flow<AttestationNftHash> = flow {
        val emitted = mutableSetOf<AttestationNftHash>()
        repository.subscribeMintedNfts(chainId, owner, candidateHashes).collect { minted ->
            candidateHashes
                .filter { it in minted && emitted.add(it) }
                .forEach { emit(it) }
        }
    }
}
