package io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence

import android.net.Uri
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.novasama.substrate_sdk_android.extensions.toHexString

fun ByteArray.hashAsUri(): Uri {
    return Uri.parse("hash://${toHexString(withPrefix = false)}")
}

fun Uri.extractHash(): ByteArray {
    return host!!.fromHex()
}
