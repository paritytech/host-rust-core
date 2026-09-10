package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.InstructionsFileSharing
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId

interface TattooReservedDetailsInteractor {
    suspend fun getInstructionsFileName(tattooId: TattooId, metadata: TattooFamilyMetadata?): String

    suspend fun prepareInstructionsFile(tattooId: TattooId, familyId: ByteArray, metadata: TattooFamilyMetadata?): InstructionsFileSharing
}

class RealTattooReservedDetailsInteractor(
    private val instructionsAttachmentUseCase: InstructionsAttachmentUseCase
) : TattooReservedDetailsInteractor {
    override suspend fun getInstructionsFileName(
        tattooId: TattooId,
        metadata: TattooFamilyMetadata?
    ): String = instructionsAttachmentUseCase.getInstructionsFileName(tattooId, metadata)

    override suspend fun prepareInstructionsFile(
        tattooId: TattooId,
        familyId: ByteArray,
        metadata: TattooFamilyMetadata?
    ): InstructionsFileSharing = instructionsAttachmentUseCase.prepareInstructionsFile(tattooId, familyId, metadata)
}
