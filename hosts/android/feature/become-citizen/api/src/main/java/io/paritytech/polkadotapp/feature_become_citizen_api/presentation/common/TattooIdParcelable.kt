package io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common

import android.os.Parcelable
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.ProceduralSeed
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId.Companion.intoPersonId
import kotlinx.parcelize.Parcelize
import java.math.BigInteger

sealed interface TattooIdParcelable : Parcelable {
    @Parcelize
    class Designed(val familyIndex: BigInteger, val index: Int) : TattooIdParcelable

    @Parcelize
    class Procedural(val familyIndex: BigInteger, val seed: ProceduralSeedParcelable) : TattooIdParcelable

    @Parcelize
    class ProceduralPersonal(val familyIndex: BigInteger, val personId: BigInteger) : TattooIdParcelable

    @Parcelize
    class ProceduralAccount(val familyIndex: BigInteger, val accountId: ByteArray) : TattooIdParcelable
}

sealed interface ProceduralSeedParcelable : Parcelable {
    @Parcelize
    class Raw(val entropy: ByteArray, val index: Int) : ProceduralSeedParcelable

    @Parcelize
    class Final(val seed: ByteArray) : ProceduralSeedParcelable
}

fun TattooId.toParcelable(): TattooIdParcelable {
    return when (this) {
        is TattooId.DesignedElective -> TattooIdParcelable.Designed(familyIndex, index)
        is TattooId.Procedural -> TattooIdParcelable.Procedural(familyIndex, seed.toParcelable())
        is TattooId.ProceduralAccount -> TattooIdParcelable.ProceduralAccount(familyIndex, accountId.value)
        is TattooId.ProceduralPersonal -> TattooIdParcelable.ProceduralPersonal(familyIndex, personId.id)
    }
}

fun TattooIdParcelable.toTattooId(): TattooId {
    return when (this) {
        is TattooIdParcelable.Designed -> TattooId.DesignedElective(familyIndex, index)
        is TattooIdParcelable.Procedural -> TattooId.Procedural(familyIndex, seed.toSeed())
        is TattooIdParcelable.ProceduralAccount -> TattooId.ProceduralAccount(familyIndex, accountId.intoAccountId())
        is TattooIdParcelable.ProceduralPersonal -> TattooId.ProceduralPersonal(familyIndex, personId.intoPersonId())
    }
}

private fun ProceduralSeed.toParcelable(): ProceduralSeedParcelable = when (this) {
    is ProceduralSeed.Final -> ProceduralSeedParcelable.Final(seed.value)
    is ProceduralSeed.Raw -> ProceduralSeedParcelable.Raw(entropy.value, index)
}

private fun ProceduralSeedParcelable.toSeed(): ProceduralSeed = when (this) {
    is ProceduralSeedParcelable.Final -> ProceduralSeed.Final(seed.toDataByteArray())
    is ProceduralSeedParcelable.Raw -> ProceduralSeed.Raw(entropy.toDataByteArray(), index)
}
