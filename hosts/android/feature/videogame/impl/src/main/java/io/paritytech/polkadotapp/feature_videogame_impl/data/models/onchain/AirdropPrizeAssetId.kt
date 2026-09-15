package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.MultiLocation.Junction
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.RelativeMultiLocation
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.junctions
import java.math.BigInteger

/**
 * The Asset Hub asset index carried by the prize Location's `GeneralIndex` junction (e.g. USDC/USDT).
 * Null when the Location has no `GeneralIndex` (i.e. not an Asset Hub asset) — callers then leave the
 * amount unscaled rather than failing the draw.
 */
fun RelativeMultiLocation.firstGeneralIndex(): BigInteger? =
    junctions.filterIsInstance<Junction.GeneralIndex>().firstOrNull()?.index
