package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import android.view.ViewGroup
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Pre-warms a [GameResultsWebViewProvider.Bundle] off-screen.
 *
 * Driver model: `VideoGameResultsPreloadInitializer` calls [startWithRetry] when
 * the game enters its early phases and [stopRetrying] when it ends. The
 * `GameResultsViewModel` consumes the warm bundle via [consume].
 *
 * Readiness is gated on `pageFinished` (i.e. `WebViewClient.onPageFinished`),
 * NOT any bridge event — bridge events fire only after input is delivered,
 * and input delivery itself waits for `pageFinished`. Gating on a bridge
 * event would deadlock. A main-frame `onReceivedError` flips the bundle's
 * `mainFrameError` flow; the retry loop rebuilds the bundle after the
 * configured delay.
 *
 * `@Singleton` so the WebView survives screen transitions.
 */
@Singleton
class GameResultsWebViewPreloader @Inject constructor(
    private val provider: GameResultsWebViewProvider
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var bundle: GameResultsWebViewProvider.Bundle? = null
    private var loaderJob: Job? = null
    private var isReady = false

    /**
     * Starts a load attempt and keeps retrying until the page reports
     * `onPageFinished`. Each retry tears the previous bundle down before
     * rebuilding, so a stuck WebView never leaks. Safe to call repeatedly:
     * a no-op while a load is in flight or a warm bundle already exists.
     */
    fun startWithRetry(retryIntervalMs: Long = DEFAULT_RETRY_INTERVAL_MS) {
        if (loaderJob?.isActive == true || isReady) return

        loaderJob = scope.launch {
            while (isActive && !isReady) {
                val attempt = provider.create()
                bundle = attempt
                provider.load(attempt)
                val succeeded = awaitLoadOutcome(attempt)
                if (succeeded) {
                    isReady = true
                } else {
                    Timber.w("[GameResults][preloader] load attempt failed; retrying in ${retryIntervalMs}ms")
                    destroyCurrentBundle()
                    delay(retryIntervalMs)
                }
            }
        }
    }

    /**
     * Cancels any in-flight retry loop and disposes of an unconsumed warm
     * bundle. Called by the driver when the game ends; safe to call when
     * no load is in flight.
     */
    fun stopRetrying() {
        if (loaderJob == null && bundle == null) return

        loaderJob?.cancel()
        loaderJob = null
        destroyCurrentBundle()
        isReady = false
    }

    /**
     * Returns the warmed bundle (detached from any parent view) if the
     * page has finished loading, otherwise `null`. Ownership of the
     * returned bundle transfers to the caller — the preloader resets and
     * stops retrying until the driver next calls [startWithRetry].
     */
    fun consume(): GameResultsWebViewProvider.Bundle? {
        val b = bundle
        if (b == null || !isReady) {
            return null
        }

        bundle = null
        loaderJob?.cancel()
        loaderJob = null
        isReady = false

        (b.webView.parent as? ViewGroup)?.removeView(b.webView)

        return b
    }

    /**
     * Suspends until the attempt either reports `pageFinished = true` (returns true)
     * or `mainFrameError = true` (returns false).
     */
    private suspend fun awaitLoadOutcome(attempt: GameResultsWebViewProvider.Bundle): Boolean {
        val finishedWatch = scope.launch { attempt.pageFinished.first { it } }
        val errorWatch = scope.launch { attempt.mainFrameError.first { it } }
        return try {
            select {
                finishedWatch.onJoin { true }
                errorWatch.onJoin { false }
            }
        } finally {
            finishedWatch.cancel()
            errorWatch.cancel()
        }
    }

    private fun destroyCurrentBundle() {
        bundle?.destroy()
        bundle = null
    }

    private companion object {
        const val DEFAULT_RETRY_INTERVAL_MS = 5_000L
    }
}
