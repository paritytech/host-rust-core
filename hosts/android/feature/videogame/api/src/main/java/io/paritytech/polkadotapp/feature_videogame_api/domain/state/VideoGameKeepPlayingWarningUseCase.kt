package io.paritytech.polkadotapp.feature_videogame_api.domain.state

import kotlinx.coroutines.flow.Flow

interface VideoGameKeepPlayingWarningUseCase {
    fun userAcknowledgedWarning(): Flow<Boolean>
}
