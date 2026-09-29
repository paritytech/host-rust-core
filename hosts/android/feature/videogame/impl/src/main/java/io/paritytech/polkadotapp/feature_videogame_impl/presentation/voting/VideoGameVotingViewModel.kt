package io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.disable
import io.paritytech.polkadotapp.common.utils.enable
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.updateItem
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsInteractor
import io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor.VideoGameVoteInteractor
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.Vote
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults.GameResultsPayload
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.models.PlayerVotingUiModel
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class VideoGameVotingViewModel @Inject constructor(
    private val interactor: VideoGameVoteInteractor,
    private val gameResultsInteractor: GameResultsInteractor,
    private val router: VideoGameRouter
) : BaseViewModel(), VideoGameVotingContract {
    private val unknownPlayers = mutableSetOf<AccountId>()
    override val players = MutableStateFlow<ImmutableList<PlayerVotingUiModel>>(persistentListOf())

    override val inProgress = MutableStateFlow(false)

    override val autoConfirm = MutableStateFlow(true)

    init {
        launch {
            val bannedIds = interactor.getBannedAccountIds()

            players.value = interactor.getVotesForCurrentGame()
                .groupBy { it.accountId }
                .mapNotNull { (accountId, playerVotes) ->
                    val participatedVotes = playerVotes.filterNot { it.vote == Vote.NotParticipated }
                    if (participatedVotes.isEmpty()) {
                        unknownPlayers.add(accountId)
                        return@mapNotNull null
                    }

                    val (personVotes, nonPersonVotes) = participatedVotes.partition { it.vote is Vote.Person }
                    val majority = personVotes.size > nonPersonVotes.size

                    PlayerVotingUiModel(
                        accountId = accountId,
                        picture = interactor.getFrameUri(accountId),
                        isPerson = majority
                    )
                }
                .filter { it.accountId !in bannedIds }
                .toImmutableList()
        }
    }

    override fun togglePlayerVote(player: PlayerVotingUiModel) {
        autoConfirm.value = false

        players.updateItem(
            condition = { it == player },
            updater = { it.copy(isPerson = !it.isPerson) }
        )
    }

    override fun confirm() = launchUnit {
        if (inProgress.value) return@launchUnit
        inProgress.enable()

        val unknownVotes = unknownPlayers.toNonPersonVotes()
        val knownVotes = players.getFinalVotes()

        interactor
            .submitVotes(knownVotes + unknownVotes)
            .onSuccess { handleVotesSubmitted() }
            .onFailure { showError(it) }

        inProgress.disable()
    }

    private fun handleVotesSubmitted() = launch {
        val payload = GameResultsPayload.from(gameResultsInteractor.buildGameResults(), showTopBar = true)
        router.openGameResults(payload)
    }

    private fun StateFlow<List<PlayerVotingUiModel>>.getFinalVotes() = value
        .associateBy(
            keySelector = { it.accountId },
            valueTransform = { it.isPerson }
        )

    private fun Set<AccountId>.toNonPersonVotes() = associateWith { false }
}
