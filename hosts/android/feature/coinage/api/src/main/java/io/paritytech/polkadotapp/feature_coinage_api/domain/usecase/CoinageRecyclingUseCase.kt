package io.paritytech.polkadotapp.feature_coinage_api.domain.usecase

import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin

interface CoinageRecyclingUseCase {
    suspend fun recycle(coins: List<Coin>): Result<Unit>
}
