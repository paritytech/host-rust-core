package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.common.utils.wrapIntoResult
import io.paritytech.polkadotapp.feature_videogame_impl.utils.VideoGameLaunchCoordinator
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

@HiltViewModel
internal class WeeklyGamePillInlineViewModel @Inject constructor(
    private val launchCoordinator: VideoGameLaunchCoordinator,
    pillStateProducer: WeeklyGamePillStateProducer,
) : BaseViewModel() {
    val pillState: StateFlow<VideoGamePillState?> = pillStateProducer.pillState()
        .wrapIntoResult()
        .map { it.getOrElse { VideoGamePillState.Hidden } }
        .stateInBackground(SharingStarted.Eagerly, VideoGamePillState.Hidden)

    fun expand() = launchUnit {
        launchCoordinator.openOrLaunchGame()
    }
}
