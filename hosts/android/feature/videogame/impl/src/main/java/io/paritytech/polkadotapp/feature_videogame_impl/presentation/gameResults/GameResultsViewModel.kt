package io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults

import android.webkit.WebView
import androidx.lifecycle.SavedStateHandle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.FlowEvent
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.GameResultsWebViewPreloader
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.GameResultsWebViewProvider
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.AirdropClaimParams
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.AttestationPush
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsInput
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsInteractor
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsLiveEvent
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import javax.inject.Inject

@HiltViewModel
class GameResultsViewModel @Inject constructor(
    private val webViewProvider: GameResultsWebViewProvider,
    private val preloader: GameResultsWebViewPreloader,
    private val interactor: GameResultsInteractor,
    private val router: VideoGameRouter,
    savedStateHandle: SavedStateHandle
) : BaseViewModel(), GameResultsContract {
    private val payload: GameResultsPayload = savedStateHandle.getPayload()
    private val input: GameResultsInput = payload.toDomain()

    // Claim params captured at results-build time; refreshed from each resolved input. Used at claim
    // time so the claim never re-resolves a post-game roster (which returns null and drops the claim).
    private var claimParams: AirdropClaimParams? = input.claim

    private val warmBundle = preloader.consume()
    private val bundle = warmBundle ?: webViewProvider.create()

    override val webView: WebView = bundle.webView

    override val showTopBar: Boolean = payload.showTopBar

    init {
        // The warm bundle was already navigated by the preloader; a cold one still needs it.
        if (warmBundle == null) launch { webViewProvider.load(bundle) }

        // Input must wait for `pageFinished` — earliest moment per the JS app's pre-mount buffer.
        bundle.pageFinished
            .filter { it }
            .take(1)
            .onEach {
                // Mirror iOS: hold the first delivery briefly while the chain resolves the verdict
                // so the initial payload already carries the outcome. A failed/slow game falls
                // through after the hold and upgrades mid-stream as before (see deliverUpgrade).
                val current = awaitResolvedInput()
                current.claim?.let { claimParams = it }
                bundle.sender.deliverInput(current)
                if (current.attestations.passed) bundle.sender.deliverOutcome(current)
                streamAttestations(current)
            }
            .launchIn(this)

        bundle.bridge.events
            .onEach(::handleEvent)
            .launchIn(this)
    }

    override fun onCleared() {
        bundle.destroy()
        super.onCleared()
    }

    override fun onCloseClick() {
        router.back()
    }

    override fun onBackPressed() {
        router.back()
    }

    private fun handleEvent(event: FlowEvent) {
        when (event) {
            FlowEvent.RequestDisplayName -> deliverFallbackDisplayName()
            is FlowEvent.UsernameAvailabilityNeeded -> deliverUsernameAvailability(event.name)
            FlowEvent.Complete -> router.back()
            is FlowEvent.PrizeDrawComplete -> if (event.won) claimAirdropPrize()
            is FlowEvent.Error ->
                Timber.w("[GameResults] flow.error phase=${event.phase} detail=${event.detail}")
            is FlowEvent.Unknown -> Timber.w("[GameResults] unknown event type=${event.type}")
            // Purely informational beats — no native action.
            FlowEvent.Ready,
            FlowEvent.ResultsShown,
            FlowEvent.PrizeDrawStarted,
            is FlowEvent.NftRevealStarted,
            FlowEvent.NftRevealComplete,
            FlowEvent.UsernameClaimRequested -> Unit
        }
    }

    private fun claimAirdropPrize() {
        val params = claimParams
        Timber.d("[Airdrop] claim TRIGGERED (prize_draw_complete won) params=$params")
        launch { interactor.claimAirdropPrize(params) }
    }

    // Waits (bounded) for the mid-stream pass upgrade so the FIRST payload carries the verdict +
    // prize; the timeout stays well under the webview's 30s boot limit. Returns the original input
    // when already resolved or when the hold expires (genuinely failed games never upgrade).
    private suspend fun awaitResolvedInput(): GameResultsInput {
        if (input.attestations.passed) return input
        return withTimeoutOrNull(OUTCOME_RESOLVE_HOLD_MS) {
            interactor.subscribeLiveResults(input)
                .filterIsInstance<GameResultsLiveEvent.UpgradedToPassed>()
                .firstOrNull()
                ?.input
        } ?: input
    }

    /**
     * Streams matched attestations to the NFT-reveal shelf (staggered), then keeps the screen
     * current from the live subscription: late mints top the shelf up, and a mid-stream
     * attendance confirmation re-delivers the payload as passed and fills the shelf.
     * Native owns the shelf; the webview fills only what it receives.
     */
    private fun streamAttestations(current: GameResultsInput) = launch {
        val shelfSize = current.attestations.total
        val streamed = streamInitialAttestations(current, shelfSize)
        // A pass already streamed the full deterministic set; the live phase only serves games
        // still unresolved at open. Stop once the shelf is full.
        if (streamed >= shelfSize || current.attestations.passed) return@launch
        consumeLiveEvents(current, startIndex = streamed, shelfSize = shelfSize)
    }

    private fun streamInitialAttestations(current: GameResultsInput, shelfSize: Int): Int {
        var index = 0
        current.attestationHashes.take(shelfSize).forEach { hash ->
            bundle.sender.pushAttestation(AttestationPush(index = index++, hash = hash, highValue = null))
        }
        return index
    }

    private suspend fun consumeLiveEvents(current: GameResultsInput, startIndex: Int, shelfSize: Int) {
        var nextIndex = startIndex
        interactor.subscribeLiveResults(current)
            .takeWhile { nextIndex < shelfSize }
            .collect { event ->
                nextIndex = when (event) {
                    is GameResultsLiveEvent.AttestationMinted -> {
                        bundle.sender.pushAttestation(
                            AttestationPush(index = nextIndex, hash = event.hash, highValue = null)
                        )
                        nextIndex + 1
                    }

                    is GameResultsLiveEvent.UpgradedToPassed -> deliverUpgrade(event, nextIndex)
                }
            }
    }

    private fun deliverUpgrade(event: GameResultsLiveEvent.UpgradedToPassed, startIndex: Int): Int {
        event.input.claim?.let { claimParams = it }
        bundle.sender.deliverInput(event.input)
        bundle.sender.deliverOutcome(event.input)
        var index = startIndex
        event.padHashes.forEach { hash ->
            bundle.sender.pushAttestation(AttestationPush(index = index++, hash = hash, highValue = null))
        }
        return index
    }

    private fun deliverUsernameAvailability(name: String) = launch {
        val availability = interactor.resolveUsernameAvailability(name)
        bundle.sender.deliverUsernameAvailability(availability = availability, alternatives = null)
    }

    private fun deliverFallbackDisplayName() {
        val name = input.member.displayName ?: return
        bundle.sender.deliverDisplayName(name)
    }

    private companion object {
        const val OUTCOME_RESOLVE_HOLD_MS = 12_000L
    }
}
