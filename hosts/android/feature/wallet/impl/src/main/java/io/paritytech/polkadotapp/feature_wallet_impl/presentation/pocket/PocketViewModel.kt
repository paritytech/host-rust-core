package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.loading.dataOrNull
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.presentation.sharing.SharingManager
import io.paritytech.polkadotapp.common.utils.ContentSharing
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.inBackground
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.common.utils.withLoading
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.BackupProgress
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.formatFiat
import io.paritytech.polkadotapp.feature_tokens_api.presentation.mapper.TokenAmountMapper
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.RoundPrecision
import io.paritytech.polkadotapp.feature_videogame_api.domain.collectibles.CollectiblesUrlResolver
import io.paritytech.polkadotapp.feature_wallet_impl.PocketRouter
import io.paritytech.polkadotapp.feature_wallet_impl.domain.interactor.PocketInteractor
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketCardUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketScreenState
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class PocketViewModel @Inject constructor(
    interactor: PocketInteractor,
    private val tokenAmountMapper: TokenAmountMapper,
    private val tokenAmountFormatter: TokenAmountFormatter,
    private val router: PocketRouter,
    private val collectiblesUrlResolver: CollectiblesUrlResolver,
    private val idShareImageRenderer: IdShareImageRenderer,
    private val sharingManager: SharingManager
) : BaseViewModel() {
    private val selectedCardId = MutableStateFlow<String?>(null)
    private val collectiblesShown = MutableStateFlow(false)

    private val digitalDollarAmounts = interactor.observeDigitalDollarBalance()
        .map { balance ->
            PocketCardUiModel.DigitalDollar.Amounts(
                balance = tokenAmountMapper.mapFrom(balance.total),
                available = tokenAmountMapper.mapFrom(balance.available)
            )
        }
        .withLoading("PocketViewModel: Failed to observe digital dollar balance")

    // Both upstreams start unresolved so the card is on screen from the first frame, shimmering its
    // amount, instead of appearing only once a balance arrives.
    private val balanceCard = combine(
        digitalDollarAmounts,
        interactor.observeBackupProgress().onStart { emit(BackupProgress.Unknown) },
    ) { amounts, backupProgress ->
        PocketCardUiModel.DigitalDollar(
            amounts = amounts,
            syncInProgress = backupProgress.isInProgress()
        )
    }

    private val addressCard = combine<_, _, _, PocketCardUiModel.IdCard?>(
        interactor.observeUsername(),
        interactor.observeRank(),
        interactor.observeAddress()
    ) { username, rank, address ->
        PocketCardUiModel.IdCard(username = username, address = address, rank = rank)
    }.onStart { emit(null) }

    val cards = combine(balanceCard, addressCard) { balance, address ->
        listOfNotNull(balance, address).toImmutableList()
    }
        .distinctUntilChangedBy { cards -> cards.map(::cardDisplayKey) }
        .inBackground()
        .stateIn(
            scope = this,
            started = SharingStarted.Eagerly,
            initialValue = persistentListOf()
        )

    val collectiblesAvailable = flowOf {
        collectiblesUrlResolver.resolveUrl() != null
    }
        .stateInBackground(initialValue = false)

    val state: StateFlow<PocketScreenState> = combine(
        cards,
        selectedCardId,
        collectiblesShown,
        collectiblesAvailable
    ) { cards, selectedId, collectiblesShown, collectiblesAvailable ->
        val selectedCard = cards.firstOrNull { it.id == selectedId }
        when {
            selectedCard != null -> PocketScreenState.CardDetails(selectedCard = selectedCard)
            collectiblesShown -> PocketScreenState.Collectibles
            else -> PocketScreenState.List(collectiblesAvailable = collectiblesAvailable)
        }
    }
        .stateIn(
            scope = this,
            started = SharingStarted.Eagerly,
            initialValue = PocketScreenState.List(collectiblesAvailable = false)
        )

    private fun cardDisplayKey(card: PocketCardUiModel): String = when (card) {
        is PocketCardUiModel.DigitalDollar -> {
            val amounts = card.amounts.dataOrNull

            listOf(
                amounts?.let {
                    tokenAmountFormatter.formatTokenAmount(it.balance, RoundPrecision.FIAT, withSymbol = false)
                },
                amounts?.let { tokenAmountFormatter.formatFiat(it.available) },
                card.syncInProgress,
                amounts?.notFullyAvailable
            ).joinToString("|")
        }

        is PocketCardUiModel.IdCard -> listOf(card.username, card.address, card.rank).joinToString("|")
    }

    fun selectCard(card: PocketCardUiModel) {
        selectedCardId.value = card.id
    }

    fun dismissCard() {
        selectedCardId.value = null
    }

    fun showCollectiblesSketchbook() {
        collectiblesShown.value = true
    }

    fun hideCollectiblesSketchbook() {
        collectiblesShown.value = false
    }

    fun openCollectibles() {
        router.openCollectibles()
    }

    fun onShareId() = launchUnit {
        val idCard = cards.value.filterIsInstance<PocketCardUiModel.IdCard>().firstOrNull() ?: return@launchUnit
        val text = "${idCard.username}\n${idCard.address}"

        idShareImageRenderer.render(idCard.username, idCard.address)
            .logFailure("PocketViewModel: failed to render ID share image")
            .onSuccess { uri ->
                sharingManager.shareContent(
                    ContentSharing.file(
                        text = text,
                        uri = uri,
                        mimeType = "image/jpeg"
                    )
                )
            }
            .onFailure { sharingManager.shareText(text) }
    }
}
