package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails

import androidx.lifecycle.SavedStateHandle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.common.presentation.loading.asLoaded
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.TattooCollection
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.TattooFamilyDetailsInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.getNotTakenTattoos
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.model.TattooPreview
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.parcel.TattooFamilyIdentifierParcelable
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.models.TattooFamilyDetailsPreviewUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.models.TattooFamilyDetailsUiModel
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class TattooFamilyDetailsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val router: BecomeCitizenRouter,
    private val tattooImageLoader: TattooImageLoader,
    private val interactor: TattooFamilyDetailsInteractor
) : BaseViewModel(), TattooFamilyDetailsContract {
    private val payload: TattooFamilyDetailsPayload = savedStateHandle.getPayload()

    override val familyDetails: StateFlow<LoadingState<TattooFamilyDetailsUiModel>> = flowOf {
        getFamilyDetailUiModel()?.asLoaded() ?: LoadingState.Error(Throwable("Failed to load family list"))
    }
        .stateIn(this, SharingStarted.Eagerly, LoadingState.Loading)

    override fun onBackClick() {
        router.back()
    }

    override fun onPreviewClick(preview: TattooFamilyDetailsPreviewUiModel) {
        router.openTattooDetails(preview.id, preview.familyId)
    }

    private suspend fun getFamilyDetailUiModel(): TattooFamilyDetailsUiModel? {
        return when (val identifier = payload.identifier) {
            is TattooFamilyIdentifierParcelable.Single -> interactor.getCollection(identifier.index).map { it.toDesignedUi() }
            is TattooFamilyIdentifierParcelable.Merged -> interactor.getCollections(identifier.indexes).map { it.toPersonalUi() }
        }.getOrNull()
    }

    private fun List<TattooPreview>.toUi(familyId: ByteArray, tattooImageLoader: TattooImageLoader) =
        map { preview ->
            TattooFamilyDetailsPreviewUiModel(
                id = preview.id,
                image = tattooImageLoader.getTattooImage(preview.id, familyId),
                familyId = familyId.toDataByteArray()
            )
        }

    private fun TattooCollection.toDesignedUi(): TattooFamilyDetailsUiModel {
        val previews = getNotTakenTattoos().toUi(familyId, tattooImageLoader)

        return TattooFamilyDetailsUiModel.Designed(
            title = metadata.name,
            description = metadata.description,
            previews = previews.toImmutableList()
        )
    }

    private fun Collection<TattooCollection>.toPersonalUi(): TattooFamilyDetailsUiModel? {
        val previews = flatMap {
            it.getNotTakenTattoos().toUi(it.familyId, tattooImageLoader)
        }

        return if (previews.isNotEmpty()) {
            TattooFamilyDetailsUiModel.Personal(
                previews = previews.toImmutableList()
            )
        } else {
            null
        }
    }
}
