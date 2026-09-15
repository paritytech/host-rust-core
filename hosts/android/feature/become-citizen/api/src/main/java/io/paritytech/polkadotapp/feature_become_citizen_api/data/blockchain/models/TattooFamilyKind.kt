package io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models

import io.paritytech.polkadotapp.chains.network.binding.bindByteArray
import io.paritytech.polkadotapp.chains.network.binding.bindInt
import io.paritytech.polkadotapp.common.data.substrate.castToDictEnum
import io.paritytech.polkadotapp.common.data.substrate.castToStruct
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyKind
import java.math.BigInteger

fun bindTattooFamily(
    decoded: Any,
    key: BigInteger,
): TattooFamily {
    val asStruct = decoded.castToStruct()

    return TattooFamily(
        kind = bindTattooFamilyKind(asStruct["kind"], key),
        id = bindByteArray(asStruct["id"])
    )
}

private fun bindTattooFamilyKind(
    decoded: Any?,
    key: BigInteger,
): TattooFamilyKind {
    val asEnum = decoded.castToDictEnum()

    return when (asEnum.name) {
        "Designed" ->
            TattooFamilyKind.Designed(
                index = key,
                count = bindInt(asEnum.value.castToStruct()["count"])
            )

        "Procedural" ->
            TattooFamilyKind.Procedural(
                index = key,
                range = bindInt(asEnum.value.castToStruct()["range"])
            )

        "ProceduralAccount" -> TattooFamilyKind.ProceduralAccount(key)
        "ProceduralPersonal" -> TattooFamilyKind.ProceduralPersonal(key)

        else -> error("Unsupported")
    }
}
