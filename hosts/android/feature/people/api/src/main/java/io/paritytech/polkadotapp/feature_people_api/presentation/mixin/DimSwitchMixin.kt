package io.paritytech.polkadotapp.feature_people_api.presentation.mixin

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimId
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

interface DimSwitchMixin {
    val dimSwitchState: StateFlow<State>
    val unavailableEvents: SharedFlow<Unit>

    fun onEditClick()
    fun onSwitchConfirm()
    fun onSwitchCancel()

    interface Factory {
        fun create(
            computationalScope: ComputationalScope,
            currentDimId: DimId,
            onError: (Throwable) -> Unit
        ): DimSwitchMixin
    }

    data class State(
        val bottomSheetVisible: Boolean = false,
        val inProgress: Boolean = false
    )

    companion object {
        const val ASSISTED_CURRENT_DIM_ID = "currentDimId"
    }
}

context(scope: ComputationalScope)
fun DimSwitchMixin.Factory.create(
    currentDimId: DimId,
    onError: (Throwable) -> Unit
): DimSwitchMixin = create(
    computationalScope = scope,
    currentDimId = currentDimId,
    onError = onError
)
