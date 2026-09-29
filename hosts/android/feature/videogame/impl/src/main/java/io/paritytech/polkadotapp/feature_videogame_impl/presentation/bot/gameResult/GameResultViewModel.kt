package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.gameResult

import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter

@HiltViewModel(assistedFactory = GameResultViewModel.Factory::class)
class GameResultViewModel @AssistedInject constructor(
    private val router: VideoGameRouter,
    @Assisted gameIndex: Int
) : BaseViewModel(), GameResultContract {
    private val gameIndex = GameIndex(gameIndex)

    @AssistedFactory
    interface Factory {
        fun create(gameIndex: Int): GameResultViewModel
    }

    override fun onChatWithPlayersClick() {
        router.openChatWithPlayers(gameIndex)
    }
}
