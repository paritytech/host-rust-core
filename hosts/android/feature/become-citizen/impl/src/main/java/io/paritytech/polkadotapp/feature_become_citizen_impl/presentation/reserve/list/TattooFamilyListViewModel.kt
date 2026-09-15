package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.common.presentation.loading.dataOrNull
import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.disable
import io.paritytech.polkadotapp.common.utils.enable
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.common.utils.stateInBackgroundWithLoading
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.ProceduralAccountTattooCollection
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.ProceduralPersonalTattooCollection
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.TattooCollection
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.TattooFamilyListInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.getNotTakenTattoos
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.model.CandidateApplicableState
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.model.TattooPreview
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.CandidateApplicableUiState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooFamilyUiIdentifier
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.parcel.toParcelable
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.TattooFamilyDetailsPayload
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.models.TattooFamilyUiModel
import io.paritytech.polkadotapp.feature_tokens_api.domain.AssetDisplayMapper
import io.paritytech.polkadotapp.feature_tokens_api.domain.requireDisplayOf
import io.paritytech.polkadotapp.feature_tokens_api.presentation.mapper.TokenAmountMapper
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.sample
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import kotlin.collections.map
import kotlin.time.Duration.Companion.milliseconds
import io.paritytech.polkadotapp.common.R as RCommon

@HiltViewModel
class TattooFamilyListViewModel @Inject constructor(
    private val interactor: TattooFamilyListInteractor,
    private val tattooImageLoader: TattooImageLoader,
    private val router: BecomeCitizenRouter,
    private val contextManager: ContextManager,
    private val tokenAmountMapper: TokenAmountMapper,
    private val assetDisplayMapper: AssetDisplayMapper
) : BaseViewModel(), TattooFamilyListContract {
    private val tattooCollectionsFlow = MutableStateFlow(emptyList<TattooCollection>())

    private val candidateApplicableState = interactor.subscribeApplicableState()
        .shareInBackground(SharingStarted.Eagerly)

    override val candidateApplicable = candidateApplicableState
        .mapLatest { it.toUi() }
        .stateInBackgroundWithLoading()

    override val tattooFamilies = tattooCollectionsFlow
        .map { collections -> LoadingState.Loaded(collections.toUi()) }
        .stateInBackground(initialValue = LoadingState.Loading)

    override val applyInProgress = MutableStateFlow(false)
    override val depositInProgress = MutableStateFlow(false)

    init {
        launch { waitForAppliedAndRefresh() }
        launch { refreshTattooList() }
    }

    override fun depositClicked() = launchUnit {
        when (val state = candidateApplicable.value.dataOrNull) {
            is CandidateApplicableUiState.NotEnoughBalance -> {
                depositInProgress.enable()

                interactor.deposit(state.requiredAmount.amount)
                    .logFailure("Failed to fund candidate account with DOT")
                    .onFailure {
                        showMessage("Failed to fund account")
                        depositInProgress.disable()
                    }
            }

            else -> Unit
        }
    }

    override fun selectFamily(family: TattooFamilyUiModel) {
        router.openTattooFamilyDetails(TattooFamilyDetailsPayload(family.identifier.toParcelable()))
    }

    override fun onBackClick() {
        router.back()
    }

    override fun applyClick() = launchUnit {
        applyInProgress.enable()

        interactor.apply()
            .onSuccess {
                Timber.d("Applied successfully")
            }
            .onFailure {
                Timber.e(it, "Could not apply")
                showError("Failed to apply: ${it.message}")
                applyInProgress.disable()
            }
    }

    private suspend fun waitForAppliedAndRefresh() {
        candidateApplicableState
            .first { it is CandidateApplicableState.Applied }

        refreshTattooList()
    }

    private fun refreshTattooList() {
        interactor.getTattooCollections()
            .sample(100.milliseconds)
            .onEach { tattooCollectionsFlow.value = it }
            .launchIn(this)
    }

    fun List<TattooPreview>.toUi(familyId: ByteArray, tattooImageLoader: TattooImageLoader) =
        map { preview -> tattooImageLoader.getTattooImage(preview.id, familyId) }

    private fun Collection<TattooCollection>.toUi(): List<TattooFamilyUiModel> {
        val (merged, separate) = partition { it is ProceduralPersonalTattooCollection || it is ProceduralAccountTattooCollection }

        return buildList {
            val mergedPreviews = merged.flatMap {
                it.getNotTakenTattoos().toUi(it.familyId, tattooImageLoader)
            }

            if (mergedPreviews.isNotEmpty()) {
                add(
                    TattooFamilyUiModel(
                        identifier = TattooFamilyUiIdentifier.Merged(merged.map { it.familyIndex }),
                        name = contextManager.applicationContext.getString(RCommon.string.tattoo_families_personal_tattoos_title),
                        totalCount = mergedPreviews.size,
                        exampleTattoos = mergedPreviews.toImmutableList()
                    )
                )
            }
            addAll(
                separate.mapNotNull {
                    val previews = it.getNotTakenTattoos()
                    val uiModels = previews.take(3).toUi(it.familyId, tattooImageLoader)

                    if (previews.isNotEmpty()) {
                        TattooFamilyUiModel(
                            identifier = TattooFamilyUiIdentifier.Single(it.familyIndex),
                            name = it.metadata.name,
                            totalCount = previews.size,
                            exampleTattoos = uiModels.toImmutableList()
                        )
                    } else {
                        null
                    }
                }
            )
        }
    }

    private fun CandidateApplicableState.toUi(): CandidateApplicableUiState {
        return when (this) {
            is CandidateApplicableState.Applied ->
                CandidateApplicableUiState.Applied

            is CandidateApplicableState.Unexpected ->
                CandidateApplicableUiState.Unexpected

            is CandidateApplicableState.CanApply ->
                CandidateApplicableUiState.CanApply(tokenAmountMapper.mapFrom(currentAmount))

            is CandidateApplicableState.NotEnoughBalance -> CandidateApplicableUiState.NotEnoughBalance(
                requiredAmount = tokenAmountMapper.mapFrom(requiredAmount),
                assetDisplay = assetDisplayMapper.requireDisplayOf(requiredAmount.chainAsset)
            )
        }
    }
}
