package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.AsTuple
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.annotations.EnumIndex
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.serialization.Serializable
import java.math.BigInteger

@Serializable
sealed interface TattooId {
    val familyIndex: TattooFamilyIndex

    @Serializable
    @AsTuple
    @EnumIndex(0)
    data class DesignedElective(override val familyIndex: TattooFamilyIndex, val index: Int) : TattooId

    @Serializable
    @AsTuple
    @EnumIndex(1)
    data class Procedural(override val familyIndex: TattooFamilyIndex, val seed: ProceduralSeed) : TattooId

    @Serializable
    @AsTuple
    @EnumIndex(2)
    data class ProceduralPersonal(override val familyIndex: TattooFamilyIndex, val personId: PersonId) : TattooId

    @Serializable
    @AsTuple
    @EnumIndex(3)
    data class ProceduralAccount(override val familyIndex: TattooFamilyIndex, val accountId: AccountId) : TattooId
}

typealias DesignedTattooFlatId = Pair<TattooFamilyIndex, BigInteger>
