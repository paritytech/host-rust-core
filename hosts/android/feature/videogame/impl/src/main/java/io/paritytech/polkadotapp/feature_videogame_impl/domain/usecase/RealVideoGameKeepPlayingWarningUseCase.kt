package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGameKeepPlayingWarningUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameKeepPlayingWarningRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class RealVideoGameKeepPlayingWarningUseCase @Inject constructor(
    private val repository: VideoGameKeepPlayingWarningRepository,
) : VideoGameKeepPlayingWarningUseCase {
    override fun userAcknowledgedWarning(): Flow<Boolean> {
        return repository.userAcknowledgedWarningFlow()
    }
}
