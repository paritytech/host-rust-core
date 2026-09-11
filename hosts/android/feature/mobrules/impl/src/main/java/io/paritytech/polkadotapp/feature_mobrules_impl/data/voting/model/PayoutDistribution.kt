package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model

import kotlinx.serialization.Serializable

@Serializable
class PayoutDistribution(
    val round: PayoutRoundIndex,
)
