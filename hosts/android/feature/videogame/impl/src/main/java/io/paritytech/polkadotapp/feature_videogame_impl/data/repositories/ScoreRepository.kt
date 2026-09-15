package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.paritytech.polkadotapp.chains.di.LocalSourceQualifier
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.observeNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainParticipant
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.RegistrationOwnershipProof
import io.paritytech.polkadotapp.feature_videogame_impl.data.origins.ScoreOrigins
import io.paritytech.polkadotapp.feature_videogame_impl.data.participants
import io.paritytech.polkadotapp.feature_videogame_impl.data.personhoodThreshold
import io.paritytech.polkadotapp.feature_videogame_impl.data.register
import io.paritytech.polkadotapp.feature_videogame_impl.data.score
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import javax.inject.Inject

interface ScoreRepository {
    fun subscribeParticipant(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Flow<OnChainParticipant?>

    suspend fun getParticipant(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): OnChainParticipant?

    /**
     * [getParticipant] against the remote source — for reads where the local cache may lag the
     * chain (e.g. recognition flipping right after a game decides the airdrop proof variant).
     */
    suspend fun getParticipantFresh(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Result<OnChainParticipant?>

    fun subscribePersonhoodThreshold(chainId: ChainId): Flow<Int>

    suspend fun generateProofOfOwnershipMessage(accountId: AccountId): ByteArray

    suspend fun register(chain: Chain, ownershipProof: RegistrationOwnershipProof?): Result<Unit>
}

fun ScoreRepository.subscribeOurParticipant(
    chainId: ChainId,
    ourAccountId: AccountId,
    ourScoreAlias: PersonalAlias
): Flow<OnChainParticipant?> {
    return combine(
        subscribeAccountParticipant(chainId, ourAccountId),
        subscribePersonParticipant(chainId, ourScoreAlias),
    ) { accountParticipant, personParticipant -> accountParticipant ?: personParticipant }
}

fun ScoreRepository.subscribeAccountParticipant(
    chainId: ChainId,
    accountId: AccountId,
): Flow<OnChainParticipant?> {
    return subscribeParticipant(chainId, OnChainAccountOrPerson.Account(accountId))
}

fun ScoreRepository.subscribePersonParticipant(
    chainId: ChainId,
    ourScoreAlias: PersonalAlias
): Flow<OnChainParticipant?> {
    return subscribeParticipant(chainId, OnChainAccountOrPerson.Person(ourScoreAlias))
}

suspend fun ScoreRepository.getAccountParticipantOrThrow(
    chainId: ChainId,
    player: AccountId
): OnChainParticipant {
    val result = getParticipant(chainId, OnChainAccountOrPerson.Account(player))
    return requireNotNull(result) {
        "Score participant value was null"
    }
}

class RealScoreRepository @Inject constructor(
    @RemoteSourceQualifier private val remoteStorageDataSource: StorageDataSource,
    @LocalSourceQualifier private val localStorageDataSource: StorageDataSource,
    private val extrinsicService: ExtrinsicService,
    private val scoreOrigins: ScoreOrigins,
) : ScoreRepository {
    override fun subscribeParticipant(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Flow<OnChainParticipant?> {
        return localStorageDataSource.subscribe(chainId) {
            metadata.score.participants.observe(player)
        }
    }

    override suspend fun getParticipant(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): OnChainParticipant? {
        return localStorageDataSource.query(chainId) {
            metadata.score.participants.query(player)
        }
    }

    override suspend fun getParticipantFresh(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Result<OnChainParticipant?> {
        return remoteStorageDataSource.queryCatching(chainId, at = null) {
            metadata.score.participants.query(player)
        }
    }

    override fun subscribePersonhoodThreshold(chainId: ChainId): Flow<Int> {
        return localStorageDataSource.subscribe(chainId) {
            metadata.score.personhoodThreshold.observeNonNull()
        }
    }

    override suspend fun generateProofOfOwnershipMessage(accountId: AccountId): ByteArray {
        val prefix = "pop register using".encodeToByteArray()
        return prefix + accountId.value
    }

    override suspend fun register(
        chain: Chain,
        ownershipProof: RegistrationOwnershipProof?
    ): Result<Unit> {
        return extrinsicService.submitExtrinsicAndAwaitExecution(chain, scoreOrigins.asAccountParticipant()) {
            score.register(ownershipProof)
        }
            .flattenExecutionFailure()
            .coerceToUnit()
    }
}
