package io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import kotlinx.coroutines.flow.StateFlow

interface ChainHealthMixin {
    val model: StateFlow<ChainHealthBarModel>

    interface Factory {
        fun create(scope: ComputationalScope): ChainHealthMixin
    }
}
