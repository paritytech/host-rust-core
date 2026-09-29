package io.paritytech.polkadotapp.feature_products_api.presentation.spaHost

import android.webkit.WebView
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.screens.MessageDisplay
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsLoadProgress
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow

/**
 * Factory for self-contained SPA sessions.
 *
 * A SPA session bundles a WebView and the JS↔Kotlin host-API bridge (signing, payments,
 * navigation, storage, …) for one `.dot` product, with inline same-WebView navigation
 * between `.dot` domains. The session lifetime is bound to the supplied [CoroutineScope] —
 * cancelling that scope tears down the bridge and the WebView.
 *
 * Lets features outside `feature/products/impl` host a product without taking on the
 * host-API infrastructure directly.
 */
interface SpaHost {
    context(scope: ComputationalScope, messageDisplay: MessageDisplay)
    fun createSession(initialUrl: String): SpaHostSession
}

interface SpaHostSession {
    val webView: StateFlow<WebView?>

    /** Current page URL, updated as the product navigates between `.dot` domains. */
    val currentUrl: StateFlow<String>

    /** Page load progress for the hosted product, for a progress indicator. */
    val loadProgress: StateFlow<DotNsLoadProgress>

    /** Current page title, updated as the product navigates. */
    val title: StateFlow<String>

    fun pauseConnections()

    fun resumeConnections()
}
