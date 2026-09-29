package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model

import io.paritytech.polkadotapp.chains.network.binding.Balance
import kotlinx.serialization.Serializable

@Serializable
class MobCredit(
    val voted: CaseCount,
    val correct: CaseCount,
    val cleaned: CaseCount,
    val credit: Balance
)
