package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.AttestationNftHash
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameGroupAssignment
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import javax.inject.Inject

/**
 * The attestation NFT ids the chain mints for the current player, derived from the on-chain
 * matchmaking layout: one per peer-round, hashed with the peer's resolved on-chain form
 * (`IndexToPlayer`) as attester — exactly the input of pallet-game's `mint_attendance_nfts`.
 * [expectedPeerRounds] is the count of distinct peer slots and drives the displayed score.
 */
data class GameAttestationCandidates(
    val hashes: List<AttestationNftHash>,
    val expectedPeerRounds: Int
)

class GameGroupRosterService @Inject constructor(
    private val repository: VideoGameRepositoryInternal
) {
    suspend fun computeCandidates(
        chainId: ChainId,
        at: BlockHash?,
        gameIndex: GameIndex,
        attestee: OnChainAccountOrPerson,
        maxGroupSize: Int,
        playerCount: Int
    ): Result<GameAttestationCandidates> {
        if (maxGroupSize <= 0 || playerCount <= 0) {
            return Result.success(GameAttestationCandidates(emptyList(), 0))
        }

        return repository.getPlayerIndexes(chainId, at, attestee).flatMap { myIndices ->
            if (myIndices.isEmpty()) {
                return@flatMap Result.success(GameAttestationCandidates(emptyList(), 0))
            }

            val peerKeys = VideoGameGroupAssignment.roundKeys(
                playerCount = playerCount,
                groupSize = maxGroupSize,
                playerIndexes = myIndices,
                includeSelf = false,
            )

            repository.getPlayersByIndexes(chainId, at, peerKeys).map { resolved ->
                val hashes = resolved.entries.map { (key, peer) ->
                    AttestationHashCalculator.computeHash(
                        gameIndex = gameIndex,
                        round = key.roundIndex,
                        attester = peer,
                        attestee = attestee
                    )
                }
                GameAttestationCandidates(hashes = hashes, expectedPeerRounds = peerKeys.size)
            }
        }
    }
}
