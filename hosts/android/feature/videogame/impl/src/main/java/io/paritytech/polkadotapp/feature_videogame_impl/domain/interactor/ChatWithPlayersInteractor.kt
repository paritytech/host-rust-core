package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.x25519OrNull
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.SharedSecretDerivationDomain
import io.paritytech.polkadotapp.feature_chats_api.domain.interactors.AddContactUseCase
import io.paritytech.polkadotapp.feature_chats_api.domain.username.FallbackUsernameGenerator
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.GamePlayersRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.domain.BannedPlayersRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.PlayerFrameFilePathCreator
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.GameContactOrigins
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.GamePlayer
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.PlayingAccountUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import javax.inject.Inject

interface ChatWithPlayersInteractor {
    context(scope: ComputationalScope)
    fun subscribeGamePlayers(gameIndex: GameIndex): Flow<List<GamePlayer>>

    suspend fun addGameContact(gameIndex: GameIndex, playerAccountId: AccountId): Result<Unit>
}

class RealChatWithPlayersInteractor @Inject constructor(
    private val gamePlayersRepository: GamePlayersRepository,
    private val addContactUseCase: AddContactUseCase,
    private val fallbackUsernameGenerator: FallbackUsernameGenerator,
    private val playingAccountUseCase: PlayingAccountUseCase,
    private val playerFrameFilePathCreator: PlayerFrameFilePathCreator,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val accountRepository: AccountRepository,
    private val knownChains: KnownChains,
    private val bannedPlayersRepository: BannedPlayersRepository
) : ChatWithPlayersInteractor {
    context(scope: ComputationalScope)
    override fun subscribeGamePlayers(gameIndex: GameIndex): Flow<List<GamePlayer>> = flowOfAll {
        val ourAccountId = playingAccountUseCase.getOurPlayerAccountId()
        val gamePlayersFlow = gamePlayersRepository.subscribeGamePlayers(gameIndex)
        val contactAccountIdsFlow = addContactUseCase.subscribeContactAccountIds()
        val bannedPlayersFlow = bannedPlayersRepository.subscribeBannedPlayers()

        combine(gamePlayersFlow, contactAccountIdsFlow, bannedPlayersFlow) { gamePlayers, contactAccountIds, bannedIds ->
            gamePlayers
                .filter { it != ourAccountId && it !in bannedIds }
                .map { accountId ->
                    GamePlayer(
                        accountId = accountId,
                        displayName = fallbackUsernameGenerator.generateFromAccountId(accountId),
                        avatarUri = playerFrameFilePathCreator.getEncodedUri(gameIndex.value, accountId),
                        isAdded = accountId in contactAccountIds
                    )
                }
        }
    }

    override suspend fun addGameContact(gameIndex: GameIndex, playerAccountId: AccountId): Result<Unit> {
        return runCatching {
            val communicationKey = videoGameRepository.getCommunicationIdentifier(knownChains.people, playerAccountId).getOrNull()
            requireNotNull(communicationKey) { "Player communication key not found" }

            accountRepository.getCandidateAccount() to communicationKey
        }
            .flatMap { (metaAccount, communicationKey) ->
                addContactUseCase.addContactWithChatRequest(
                    contactAccountId = playerAccountId,
                    username = null,
                    chatKey = (
                        communicationKey.x25519OrNull()
                            ?: error("Player uses an unsupported chat encryption key type")
                        ).bytes.value,
                    sharedSecretDerivationDomain = SharedSecretDerivationDomain.CANDIDATE,
                    ourMetaAccountId = metaAccount.id,
                    avatar = playerFrameFilePathCreator.getEncodedUri(gameIndex.value, playerAccountId),
                    origin = GameContactOrigins.SHARED_GAME,
                    welcomeMessage = null
                )
            }
    }
}
