package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.EvidenceLocalState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject

class EvidencePhotoCaptureInteractor @Inject constructor(
    private val storage: EvidenceStorage,
    private val evidenceLocalStateStorage: EvidenceLocalStateStorage,
    private val coroutineDispatchers: CoroutineDispatchers,
    private val tattooRepository: TattooRepository,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    private val chainRegistry: ChainRegistry,
    private val tattooImageLoader: TattooImageLoader
) {
    suspend fun getDestinationFile(): File = withContext(coroutineDispatchers.io) {
        val file = storage.getEvidenceFile(EvidenceType.PHOTO)

        if (file.exists()) {
            file.delete()
        }

        return@withContext file
    }

    suspend fun finalizePhoto() {
        evidenceLocalStateStorage.setState(EvidenceType.PHOTO, EvidenceLocalState.PRESENT)
    }

    suspend fun cancelPhoto() = withContext(coroutineDispatchers.io) {
        storage.getEvidenceFile(EvidenceType.PHOTO).delete()
    }

    fun subscribeCommitedTattooImage(): Flow<TattooImage?> = tattooProgressStateUseCase.tattooProgressStateFlow()
        .map { stateResult ->
            when (val state = stateResult.getOrNull()) {
                is TattooProgressState.Committed -> {
                    val family = tattooRepository.getDesignFamily(
                        chainRegistry.knownChains.people,
                        state.tattooId.familyIndex
                    ).getOrNull()

                    family?.let { tattooImageLoader.getTattooImage(state.tattooId, it.id) }
                }
                else -> null
            }
        }
}
