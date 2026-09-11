package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import kotlin.time.Duration

interface GetGameProcessingDurationUseCase {
    suspend operator fun invoke(): Duration
}
