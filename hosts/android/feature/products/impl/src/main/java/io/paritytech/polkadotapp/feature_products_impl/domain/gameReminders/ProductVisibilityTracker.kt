package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import androidx.core.net.toUri
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.common.presentation.subscribeIsForeground
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_products_api.domain.browser.ProductSessionController
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Which product's SPA is on screen. The session controller keeps its active tab after the browser is left, so the
 * browser screen reports whether it is resumed, and both only count while the app is in the foreground.
 */
@Singleton
class ProductVisibilityTracker @Inject constructor(
    sessionController: ProductSessionController,
    private val dotNsTldProvider: DotNsTldProvider,
    appLifecycleObserver: AppLifecycleObserver,
) {
    private val browserResumed = MutableStateFlow(false)

    val isForeground: Flow<Boolean> = appLifecycleObserver.subscribeIsForeground()

    /** The product whose SPA is on screen, `null` when none is or the app is in the background. */
    val visibleProductId: Flow<String?> = combine(
        browserResumed,
        sessionController.activeTab,
        isForeground,
    ) { resumed, tab, foreground ->
        if (resumed && foreground) tab?.url?.let(::productIdOf) else null
    }.distinctUntilChanged()

    fun setBrowserResumed(resumed: Boolean) {
        browserResumed.value = resumed
    }

    private fun productIdOf(url: String): String? {
        val tld = dotNsTldProvider.currentTldOrNull() ?: return null
        return ProductId.fromUrl(url.toUri(), tld).getOrNull()?.value
    }
}
