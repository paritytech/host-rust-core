package io.paritytech.polkadotapp.feature_products_api.presentation

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Navigation arg for the SPA sheet: which product to host for the sheet's lifetime. */
@Parcelize
data class SpaSheetPayload(val productId: String) : Parcelable
