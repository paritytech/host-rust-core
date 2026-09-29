package io.paritytech.polkadotapp.feature_videogame_impl.domain.autoLaunch

import android.Manifest
import io.paritytech.polkadotapp.common.data.app.AppLifecycleState
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppInitializer
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.isDisabled
import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker
import io.paritytech.polkadotapp.common.utils.permissions.PermissionResult
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameSnapshot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameRegistrationStageUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.service.VideoGameStateReader
import io.paritytech.polkadotapp.feature_videogame_impl.utils.VideoGameLaunchCoordinator
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class VideoGameAutoLauncher @Inject constructor(
    private val stateReader: VideoGameStateReader,
    private val registrationStageUseCase: VideoGameRegistrationStageUseCase,
    private val appLifecycleObserver: AppLifecycleObserver,
    private val permissionAsker: PermissionAsker,
    private val launchCoordinator: VideoGameLaunchCoordinator,
) : AppInitializer {
    private var lastAutoLaunchedGameIndex: GameIndex? = null

    context(scope: ComputationalScope)
    override fun initialize(): Result<Unit> = runCancellableCatching {
        if (FeatureOption.PERSONHOOD.isDisabled) return@runCancellableCatching

        combine(
            stateReader.gameSnapshot
                .map(::autoLaunchableSnapshot)
                .distinctUntilChanged(),
            registrationStageUseCase.subscribe()
                .map { it is VideoGameRegistrationStage.Registered }
                .distinctUntilChanged(),
            appLifecycleObserver.subscribe()
                .map { it == AppLifecycleState.FOREGROUND }
                .distinctUntilChanged(),
        ) { snapshot, registered, foregrounded ->
            snapshot.takeIf { registered && foregrounded }
        }
            .filterNotNull()
            .onEach { snapshot -> autoLaunch(snapshot) }
            .launchIn(scope)
    }

    private fun autoLaunchableSnapshot(snapshot: VideoGameSnapshot?): VideoGameSnapshot? {
        val state = snapshot?.processState ?: return null
        return when (state) {
            is VideoGameProcessState.Round -> snapshot
            else -> null
        }
    }

    private suspend fun autoLaunch(snapshot: VideoGameSnapshot) {
        if (snapshot.gameIndex == lastAutoLaunchedGameIndex) return
        // Already on the play screen — don't stack another instance on top.
        if (stateReader.isSessionRunning) {
            lastAutoLaunchedGameIndex = snapshot.gameIndex
            return
        }
        if (permissionAsker.getPermissionState(Manifest.permission.CAMERA) != PermissionResult.GRANTED) return
        lastAutoLaunchedGameIndex = snapshot.gameIndex
        launchCoordinator.openOrLaunchGame()
    }
}
