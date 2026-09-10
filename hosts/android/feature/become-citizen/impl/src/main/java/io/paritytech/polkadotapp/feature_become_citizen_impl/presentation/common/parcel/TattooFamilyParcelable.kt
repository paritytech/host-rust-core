package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.parcel

import android.os.Parcelable
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooFamilyUiIdentifier
import kotlinx.parcelize.Parcelize

sealed interface TattooFamilyIdentifierParcelable : Parcelable {
    @Parcelize
    class Single(val index: TattooFamilyIndex) : TattooFamilyIdentifierParcelable

    @Parcelize
    class Merged(val indexes: List<TattooFamilyIndex>) : TattooFamilyIdentifierParcelable
}

fun TattooFamilyUiIdentifier.toParcelable() = when (this) {
    is TattooFamilyUiIdentifier.Merged -> TattooFamilyIdentifierParcelable.Merged(indexes)
    is TattooFamilyUiIdentifier.Single -> TattooFamilyIdentifierParcelable.Single(index)
}

fun TattooFamilyIdentifierParcelable.toIdentifier() = when (this) {
    is TattooFamilyIdentifierParcelable.Single -> TattooFamilyUiIdentifier.Single(index)
    is TattooFamilyIdentifierParcelable.Merged -> TattooFamilyUiIdentifier.Merged(indexes)
}
