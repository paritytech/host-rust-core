package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import java.math.BigInteger

class TattooGlobalConfiguration(
    val rerollTimeout: BigInteger,
    val fasttrackCount: BigInteger,
    val maximum: BigInteger,
    val fullAllocLen: BigInteger,
    val fullAllocCount: BigInteger,
    val initAllocLen: BigInteger,
    val initAllocCount: BigInteger,
    val timeout: BigInteger
)
