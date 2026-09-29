package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import kotlinx.collections.immutable.ImmutableList

@Immutable
sealed interface TattooFamilyDetailsUiModel {
    val previews: ImmutableList<TattooFamilyDetailsPreviewUiModel>

    data class Personal(
        override val previews: ImmutableList<TattooFamilyDetailsPreviewUiModel>
    ) : TattooFamilyDetailsUiModel

    data class Designed(
        val title: String,
        val description: String,
        override val previews: ImmutableList<TattooFamilyDetailsPreviewUiModel>
    ) : TattooFamilyDetailsUiModel
}

@Immutable
data class TattooFamilyDetailsPreviewUiModel(
    val id: TattooId,
    val image: TattooImage,
    val familyId: DataByteArray
)
