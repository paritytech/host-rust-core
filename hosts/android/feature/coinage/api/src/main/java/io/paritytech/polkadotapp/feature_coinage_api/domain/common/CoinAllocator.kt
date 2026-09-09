package io.paritytech.polkadotapp.feature_coinage_api.domain.common

import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent

interface CoinAllocator {
    suspend fun allocate(valueExponent: ValueExponent): Result<Coin>

    suspend fun allocateAll(valueExponents: List<ValueExponent>): Result<List<Coin>>
}
