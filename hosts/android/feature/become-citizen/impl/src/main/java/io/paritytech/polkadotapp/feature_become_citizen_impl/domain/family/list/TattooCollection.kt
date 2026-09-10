package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.DesignedTattooFlatId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.ProceduralSeed
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyKind
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.model.TattooPreview
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId

sealed class TattooCollection(
    val familyId: ByteArray,
    val familyIndex: TattooFamilyIndex,
    val metadata: TattooFamilyMetadata,
) : AbstractList<TattooPreview>() {
    companion object {
        fun createDesigned(
            familyId: ByteArray,
            kind: TattooFamilyKind.Designed,
            metadata: TattooFamilyMetadata,
            alreadyTakenTattoos: Set<DesignedTattooFlatId>
        ) = DesignedTattooCollection(
            kind.count,
            familyId,
            kind.familyIndex,
            metadata,
            alreadyTakenTattoos
        )

        fun createProcedural(
            familyId: ByteArray,
            kind: TattooFamilyKind.Procedural,
            metadata: TattooFamilyMetadata,
            entropy: DataByteArray
        ) = ProceduralTattooCollection(
            kind.range,
            familyId,
            kind.familyIndex,
            metadata,
            entropy
        )

        fun createProceduralPersonal(
            familyId: ByteArray,
            kind: TattooFamilyKind.ProceduralPersonal,
            metadata: TattooFamilyMetadata,
            personId: PersonId
        ) = ProceduralPersonalTattooCollection(
            familyId,
            kind.familyIndex,
            metadata,
            personId
        )

        fun createProceduralAccount(
            familyId: ByteArray,
            kind: TattooFamilyKind.ProceduralAccount,
            metadata: TattooFamilyMetadata,
            accountId: AccountId
        ) = ProceduralAccountTattooCollection(
            familyId,
            kind.familyIndex,
            metadata,
            accountId
        )
    }
}

fun TattooCollection.getNotTakenTattoos() = filterNot { tattoo -> tattoo.isAlreadyTaken }

class DesignedTattooCollection(
    count: Int,
    familyId: ByteArray,
    familyIndex: TattooFamilyIndex,
    metadata: TattooFamilyMetadata,
    private val takenTattoos: Set<DesignedTattooFlatId>,
) : TattooCollection(familyId, familyIndex, metadata) {
    override val size: Int = count

    override fun get(index: Int): TattooPreview {
        require(index >= 0 || index < size) {
            "Index out of bounds: $index not in ${0}..$lastIndex"
        }

        return TattooPreview(
            id = TattooId.DesignedElective(familyIndex, index),
            isAlreadyTaken = familyIndex to index.toBigInteger() in takenTattoos
        )
    }
}

class ProceduralTattooCollection(
    range: Int,
    familyId: ByteArray,
    familyIndex: TattooFamilyIndex,
    metadata: TattooFamilyMetadata,
    private val entropy: DataByteArray
) : TattooCollection(familyId, familyIndex, metadata) {
    override val size: Int = range

    override fun get(index: Int): TattooPreview {
        require(index !in size..<0) {
            "Index out of bounds: $index not in ${0}..$lastIndex"
        }

        return TattooPreview(
            id = TattooId.Procedural(familyIndex, ProceduralSeed.Raw(entropy, index)),
            isAlreadyTaken = false
        )
    }
}

class ProceduralPersonalTattooCollection(
    familyId: ByteArray,
    familyIndex: TattooFamilyIndex,
    metadata: TattooFamilyMetadata,
    private val personId: PersonId
) : TattooCollection(familyId, familyIndex, metadata) {
    override val size: Int = 1

    override fun get(index: Int): TattooPreview {
        return TattooPreview(
            id = TattooId.ProceduralPersonal(familyIndex, personId),
            isAlreadyTaken = false
        )
    }
}

class ProceduralAccountTattooCollection(
    familyId: ByteArray,
    familyIndex: TattooFamilyIndex,
    metadata: TattooFamilyMetadata,
    private val accountId: AccountId
) : TattooCollection(familyId, familyIndex, metadata) {
    override val size: Int = 1

    override fun get(index: Int): TattooPreview {
        return TattooPreview(
            id = TattooId.ProceduralAccount(familyIndex, accountId),
            isAlreadyTaken = false
        )
    }
}
