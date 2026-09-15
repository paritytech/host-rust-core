package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common

import android.os.Parcelable
import io.paritytech.polkadotapp.common.utils.millimeters
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooPlacement
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooSize
import kotlinx.parcelize.Parcelize

@Parcelize
class FamilyMetadataDetailsParcel(
    val name: String,
    val description: String,
    val placement: TattooPlacementParcel,
    val cid: String
) : Parcelable

@Parcelize
class TattooPlacementParcel(val size: TattooSizeParcel) : Parcelable

sealed class TattooSizeParcel : Parcelable {
    @Parcelize
    class Fixed(val size: Int) : TattooSizeParcel()

    @Parcelize
    class Variable(val from: Int, val to: Int) : TattooSizeParcel()
}

fun TattooFamilyMetadata.toParcel(): FamilyMetadataDetailsParcel {
    return FamilyMetadataDetailsParcel(name, description, placement.toParcel(), cid)
}

fun TattooPlacement.toParcel(): TattooPlacementParcel {
    return TattooPlacementParcel(
        size = size.toParcel()
    )
}

fun TattooSize.toParcel(): TattooSizeParcel {
    return when (this) {
        is TattooSize.Fixed -> TattooSizeParcel.Fixed(size.value)
        is TattooSize.Variable -> TattooSizeParcel.Variable(from.value, to.value)
    }
}

fun FamilyMetadataDetailsParcel.fromParcel(): TattooFamilyMetadata {
    return TattooFamilyMetadata(name, description, placement.fromParcel(), cid)
}

fun TattooPlacementParcel.fromParcel(): TattooPlacement {
    return TattooPlacement(size.fromParcel())
}

fun TattooSizeParcel.fromParcel(): TattooSize {
    return when (this) {
        is TattooSizeParcel.Fixed -> TattooSize.Fixed(size.millimeters)
        is TattooSizeParcel.Variable -> TattooSize.Variable(from.millimeters, to.millimeters)
    }
}
