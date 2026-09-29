package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails

import android.os.Parcelable
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooIdParcelable
import kotlinx.parcelize.Parcelize

@Parcelize
class TattooDetailsPayload(
    val tattooId: TattooIdParcelable,
    val familyId: ByteArray
) : Parcelable
