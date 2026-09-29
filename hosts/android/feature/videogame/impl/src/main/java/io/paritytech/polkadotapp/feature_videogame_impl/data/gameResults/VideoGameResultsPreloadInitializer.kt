package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppInitializer
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.isDisabled
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.service.VideoGameStateReader
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Drives the game-results WebView preload off the [VideoGameStateReader] so the
 * load only runs while the game is in a "quiet" phase that doesn't compete with
 * WebRTC for bandwidth or CPU. The preloader's retry loop runs only in those
 * windows; entering an active-WebRTC phase tears the in-flight bundle down.
 */
@Singleton
class VideoGameResultsPreloadInitializer @Inject constructor(
    private val stateReader: VideoGameStateReader,
    private val preloader: GameResultsWebViewPreloader,
) : AppInitializer {
    context(scope: ComputationalScope)
    override fun initialize(): Result<Unit> = runCancellableCatching {
        if (FeatureOption.PERSONHOOD.isDisabled) return@runCancellableCatching

        stateReader.gameSnapshot
            .map { it?.processState.shouldPreload() }
            .distinctUntilChanged()
            .onEach { shouldPreload ->
                if (shouldPreload) preloader.startWithRetry() else preloader.stopRetrying()
            }
            .launchIn(scope)
    }

    private fun VideoGameProcessState?.shouldPreload(): Boolean = when (this) {
        // Pre-game lull. The session manager opens WebRTC channels only during the last
        // PRE_CONNECTION_TIME of WaitingRoom (signalled by `preConnection != null`);
        // before that, the connection is idle and the WebView load runs free.
        is VideoGameProcessState.WaitingRoom -> preConnection == null
        // Post-gameplay grading window — WebRTC has torn down, results screen not open yet.
        // Final retry window before [GameResultsViewModel.consume].
        is VideoGameProcessState.Reporting -> true
        // Active WebRTC traffic (round play + the pre-warm tail of WaitingRoom) — skip.
        is VideoGameProcessState.Round,
        is VideoGameProcessState.Finished,
        is VideoGameProcessState.Error,
        null -> false
    }
}
