package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.common.utils.mapResult
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.InstructionsFileSharing
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.ReservedTattoo
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.ReservedTattoo.ReservationState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

interface TattooReservedInteractor {
    fun reservedTattooFlow(tattooId: TattooId): Flow<Result<ReservedTattoo>>

    suspend fun getInstructionsFileName(tattooId: TattooId, metadata: TattooFamilyMetadata?): String
    suspend fun prepareInstructionsFile(tattooId: TattooId, familyId: ByteArray, metadata: TattooFamilyMetadata?): InstructionsFileSharing
}

class RealTattooReservedInteractor(
    private val tattooRepository: TattooRepository,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    private val chainRegistry: ChainRegistry,
    private val instructionsAttachmentUseCase: InstructionsAttachmentUseCase
) : TattooReservedInteractor {
    override fun reservedTattooFlow(tattooId: TattooId): Flow<Result<ReservedTattoo>> {
        return flowOfAll {
            val family = tattooRepository.getDesignFamily(chainRegistry.knownChains.people, tattooId.familyIndex).getOrNull()
            val metadata = family?.let { tattooRepository.getTattooFamilyMetadata(it.id).getOrNull() }

            if (metadata != null) {
                tattooProgressStateUseCase.tattooProgressStateFlow().mapResult {
                    ReservedTattoo(
                        id = tattooId,
                        familyId = family.id,
                        familyMetadata = metadata,
                        reservationState = it.toReservationState()
                    )
                }
            } else {
                flowOf(Result.failure(IllegalStateException("No metadata found for family ${tattooId.familyIndex}")))
            }
        }
    }

    private fun TattooProgressState.toReservationState(): ReservationState {
        return when (this) {
            is TattooProgressState.Committed -> ReservationState.WaitingForEvidence(expiration)
            is TattooProgressState.UploadingEvidence -> ReservationState.EvidenceProvided
            else -> ReservationState.Invalid
        }
    }

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
