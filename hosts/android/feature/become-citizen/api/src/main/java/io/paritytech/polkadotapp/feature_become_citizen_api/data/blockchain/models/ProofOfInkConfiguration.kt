package io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models

import io.paritytech.polkadotapp.chains.network.binding.bindNumber
import io.paritytech.polkadotapp.common.data.substrate.castToStruct
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooGlobalConfiguration

fun bindProofOfInkConfiguration(decoded: Any): TattooGlobalConfiguration {
    val asStruct = decoded.castToStruct()

    return TattooGlobalConfiguration(
        rerollTimeout = bindNumber(asStruct["rerollTimeout"]),
        fasttrackCount = bindNumber(asStruct["fasttrackCount"]),
        maximum = bindNumber(asStruct["maximum"]),
        fullAllocLen = bindNumber(asStruct["fullAllocLen"]),
        fullAllocCount = bindNumber(asStruct["fullAllocCount"]),
        initAllocLen = bindNumber(asStruct["initAllocLen"]),
        initAllocCount = bindNumber(asStruct["initAllocCount"]),
        timeout = bindNumber(asStruct["timeout"])
    )
}
