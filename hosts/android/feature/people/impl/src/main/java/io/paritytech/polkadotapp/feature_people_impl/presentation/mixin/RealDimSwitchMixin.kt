package io.paritytech.polkadotapp.feature_people_impl.presentation.mixin

import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.emit
import io.paritytech.polkadotapp.feature_people_api.domain.dim.CancelOtherDimCommitmentUseCase
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimId
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimState
import io.paritytech.polkadotapp.feature_people_api.domain.dim.GetActiveDimCommitmentState
import io.paritytech.polkadotapp.feature_people_api.presentation.mixin.DimSwitchMixin
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class RealDimSwitchMixin @AssistedInject constructor(
    @Assisted private val computationalScope: ComputationalScope,
    @Assisted(DimSwitchMixin.ASSISTED_CURRENT_DIM_ID) private val currentDimId: DimId,
    @Assisted private val onError: (Throwable) -> Unit,
    private val getActiveDimCommitmentState: GetActiveDimCommitmentState,
    private val cancelOtherDimCommitmentUseCase: CancelOtherDimCommitmentUseCase
) : DimSwitchMixin {
    override val dimSwitchState = MutableStateFlow(DimSwitchMixin.State())

    override val unavailableEvents = MutableSharedFlow<Unit>()

    override fun onEditClick() {
        with(computationalScope) {
            launch {
                val state = getActiveDimCommitmentState(currentDimId).first()
                val canCancel = (state as? DimState.Started)?.cancellable == true

                if (canCancel) {
                    dimSwitchState.update { it.copy(bottomSheetVisible = true) }
                } else {
                    unavailableEvents.emit()
                }
            }
        }
    }

    override fun onSwitchConfirm() {
        with(computationalScope) {
            launch {
                dimSwitchState.update { it.copy(inProgress = true) }

                cancelOtherDimCommitmentUseCase(currentDimId)
                    .onSuccess {
                        dimSwitchState.update {
                            it.copy(bottomSheetVisible = false, inProgress = false)
                        }
                    }
                    .onFailure { error ->
                        dimSwitchState.update { it.copy(inProgress = false) }
                        onError(error)
                    }
            }
        }
    }

    override fun onSwitchCancel() {
        dimSwitchState.update { it.copy(bottomSheetVisible = false) }
    }

    @AssistedFactory
    interface Factory : DimSwitchMixin.Factory {
        override fun create(
            computationalScope: ComputationalScope,
            @Assisted(DimSwitchMixin.ASSISTED_CURRENT_DIM_ID) currentDimId: DimId,
            onError: (Throwable) -> Unit
        ): RealDimSwitchMixin
    }
}
