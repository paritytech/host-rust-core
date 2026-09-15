package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.dim

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.filterResultSuccessNotNull
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimCommitmentHandler
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimId
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class Dim1CommitmentHandler @Inject constructor(
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    private val tattooRepository: TattooRepository,
    private val chainRegistry: ChainRegistry
) : DimCommitmentHandler {
    companion object {
        const val DIM_ID: DimId = "dim1"
    }

    override val dimId: DimId = DIM_ID

    override val botId: String = ChatBotData.tattoo().id

    context(scope: ComputationalScope)
    override fun observeState(): Flow<DimState> =
        tattooProgressStateUseCase.tattooProgressStateFlow()
            .filterResultSuccessNotNull()
            .map { state ->
                when (state) {
                    is TattooProgressState.Started -> DimState.Started(cancellable = state is TattooProgressState.Applied)
                    TattooProgressState.NotStarted,
                    TattooProgressState.Unknown -> DimState.NotStarted
                }
            }

    context(scope: ComputationalScope)
    override suspend fun cancel(): Result<Unit> =
        tattooProgressStateUseCase.getTattooProgressState().flatMap { progressState ->
            when (progressState) {
                is TattooProgressState.Applied -> {
                    tattooRepository.flakeOut(chainRegistry.peopleChain())
                }
                is TattooProgressState.NotStarted -> {
                    Result.success(Unit)
                }
                is TattooProgressState.Committed,
                is TattooProgressState.RecognizedPerson,
                is TattooProgressState.UploadingEvidence,
                is TattooProgressState.RegisteringPerson,
                is TattooProgressState.UnrecoverableFailure,
                is TattooProgressState.Unknown -> {
                    Result.failure(IllegalStateException("Cannot quit DIM1 in state ${progressState::class.simpleName}"))
                }
            }
        }
}
