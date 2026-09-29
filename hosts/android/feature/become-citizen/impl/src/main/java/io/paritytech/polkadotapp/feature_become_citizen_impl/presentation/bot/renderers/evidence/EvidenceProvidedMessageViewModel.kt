package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence

import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors.EvidenceProvidedMessageInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.models.EvidenceProvidedMessageUiModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

@HiltViewModel(assistedFactory = EvidenceProvidedMessageViewModel.Factory::class)
class EvidenceProvidedMessageViewModel @AssistedInject constructor(
    @Assisted private val evidenceType: EvidenceType,
    interactor: EvidenceProvidedMessageInteractor
) : BaseViewModel() {
    @AssistedFactory
    interface Factory {
        fun create(evidenceType: EvidenceType): EvidenceProvidedMessageViewModel
    }

    private val evidenceUri = interactor.subscribeEvidenceUri(evidenceType).shareInBackground()
    private val evidenceProvidingState = interactor.subscribeEvidenceProvidingState(evidenceType).shareInBackground()

    val message = combine(
        evidenceUri,
        evidenceProvidingState
    ) { uri, providingState ->
        EvidenceProvidedMessageUiModel(
            uri = uri,
            providingState = providingState,
            evidenceType = evidenceType
        )
    }.stateIn(this, SharingStarted.Eagerly, EvidenceProvidedMessageUiModel(evidenceType = evidenceType))
}
