package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import io.paritytech.polkadotapp.common.utils.Millimeters

class TattooFamilyMetadata(
    val name: String,
    val description: String,
    val placement: TattooPlacement,
    val cid: String,
)

class TattooPlacement(
    val size: TattooSize
)

sealed class TattooSize {
    class Fixed(val size: Millimeters) : TattooSize()

    class Variable(val from: Millimeters, val to: Millimeters) : TattooSize()
}
