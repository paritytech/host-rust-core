package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull

interface PhotoRecordInteractor {
    suspend fun getCommitedTattooImage(): TattooImage?
}

class RealPhotoRecordInteractor(
    private val tattooRepository: TattooRepository,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    private val chainRegistry: ChainRegistry,
    private val tattooImageLoader: TattooImageLoader
) : PhotoRecordInteractor {
    override suspend fun getCommitedTattooImage(): TattooImage? {
        val tattooId = tattooProgressStateUseCase.tattooProgressStateFlow()
            .mapNotNull { it.getOrNull() }
            .filterIsInstance<TattooProgressState.Committed>()
            .map { it.tattooId }
            .first()

        val family = tattooRepository.getDesignFamily(chainRegistry.knownChains.people, tattooId.familyIndex).getOrNull()

        return family?.let { tattooImageLoader.getTattooImage(tattooId, it.id) }
    }
}
