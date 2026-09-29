package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails

import android.os.Parcelable
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.parcel.TattooFamilyIdentifierParcelable
import kotlinx.parcelize.Parcelize

@Parcelize
class TattooFamilyDetailsPayload(
    val identifier: TattooFamilyIdentifierParcelable
) : Parcelable
