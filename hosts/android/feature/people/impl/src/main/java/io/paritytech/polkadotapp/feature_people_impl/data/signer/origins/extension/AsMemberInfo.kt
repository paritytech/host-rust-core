@file:Keep

package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension

import androidx.annotation.Keep
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.encode
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchSignature
import io.paritytech.polkadotapp.common.utils.scale.ToDynamicScaleInstance
import kotlinx.serialization.Serializable

@Serializable
sealed class AsMemberInfo : ToDynamicScaleInstance {
    override fun toEncodableInstance(): Any? = Scale.encode(this)

    @Serializable
    @TransientStruct
    class SelfInclude(val signature: BandersnatchSignature) : AsMemberInfo()
}
