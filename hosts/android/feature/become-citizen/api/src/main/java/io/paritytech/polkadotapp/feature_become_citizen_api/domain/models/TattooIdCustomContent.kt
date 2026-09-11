@file:OptIn(ExperimentalUnsignedTypes::class)

package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.annotations.EnumIndex
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.serialization.Serializable

@Serializable
sealed interface TattooIdCustomContent {
    val familyIndex: TattooFamilyIndex

    @Serializable
    @EnumIndex(0)
    data class DesignedElective(override val familyIndex: TattooFamilyIndex, val index: Int) : TattooIdCustomContent

    @Serializable
    @EnumIndex(1)
    data class Procedural(override val familyIndex: TattooFamilyIndex, val seed: ProceduralSeedCustomContent) : TattooIdCustomContent

    @Serializable
    @EnumIndex(2)
    data class ProceduralPersonal(override val familyIndex: TattooFamilyIndex, val personId: PersonId) : TattooIdCustomContent

    @Serializable
    @EnumIndex(3)
    data class ProceduralAccount(override val familyIndex: TattooFamilyIndex, val accountId: AccountId) : TattooIdCustomContent
}

@Serializable
sealed interface ProceduralSeedCustomContent {
    @Serializable
    @EnumIndex(0)
    data class Raw(val entropy: DataByteArray, val index: Int) : ProceduralSeedCustomContent

    @Serializable
    @EnumIndex(1)
    data class Final(val seed: DataByteArray) : ProceduralSeedCustomContent
}

fun TattooId.toCustomContent(): TattooIdCustomContent {
    return when (this) {
        is TattooId.Procedural -> TattooIdCustomContent.Procedural(familyIndex, seed.toCustomContent())
        is TattooId.DesignedElective -> TattooIdCustomContent.DesignedElective(familyIndex, index)
        is TattooId.ProceduralPersonal -> TattooIdCustomContent.ProceduralPersonal(familyIndex, personId)
        is TattooId.ProceduralAccount -> TattooIdCustomContent.ProceduralAccount(familyIndex, accountId)
    }
}

fun TattooIdCustomContent.toDomain(): TattooId {
    return when (this) {
        is TattooIdCustomContent.Procedural -> TattooId.Procedural(familyIndex, seed.toDomain())
        is TattooIdCustomContent.DesignedElective -> TattooId.DesignedElective(familyIndex, index)
        is TattooIdCustomContent.ProceduralPersonal -> TattooId.ProceduralPersonal(familyIndex, personId)
        is TattooIdCustomContent.ProceduralAccount -> TattooId.ProceduralAccount(familyIndex, accountId)
    }
}

private fun ProceduralSeed.toCustomContent(): ProceduralSeedCustomContent {
    return when (this) {
        is ProceduralSeed.Raw -> ProceduralSeedCustomContent.Raw(entropy, index)
        is ProceduralSeed.Final -> ProceduralSeedCustomContent.Final(seed)
    }
}

private fun ProceduralSeedCustomContent.toDomain(): ProceduralSeed {
    return when (this) {
        is ProceduralSeedCustomContent.Raw -> ProceduralSeed.Raw(entropy, index)
        is ProceduralSeedCustomContent.Final -> ProceduralSeed.Final(seed)
    }
}
