package io.paritytech.polkadotapp.feature_products_impl.domain.webView

import android.webkit.WebView
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.CallingProductIdProvider
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.PageLifecycleSource
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

abstract class WebViewProvider(
    private val dispatchers: CoroutineDispatchers
) : PageLifecycleSource {
    private val mutex = Mutex()
    private var cachedWebView: WebView? = null

    private val onPageFinishedListeners = mutableListOf<() -> Unit>()
    private val onPageStartedListeners = mutableListOf<(String) -> Unit>()

    private var onWebViewDestroyed: (() -> Unit)? = null

    abstract val callingProductIdProvider: CallingProductIdProvider

    protected abstract suspend fun createWebView(): WebView

    /**
     * Loads the initial content into the WebView.
     * All data needed (URL, HTML, scripts) is supplied at construction time via the factory.
     */
    abstract suspend fun loadInitialContent()

    suspend fun getWebView(): WebView {
        return mutex.withLock {
            if (cachedWebView != null) return cachedWebView!!

            withContext(dispatchers.main) { createWebView() }
                .also { cachedWebView = it }
        }
    }

    suspend fun <R> accessWebView(action: suspend (WebView) -> R): R {
        return withContext(dispatchers.main) {
            val webView = getWebView()
            action(webView)
        }
    }

    fun getWebViewOrNull(): WebView? = cachedWebView

    fun setOnWebViewDestroyed(callback: () -> Unit) {
        onWebViewDestroyed = callback
    }

    override fun addOnPageFinishedListener(listener: () -> Unit) {
        onPageFinishedListeners += listener
    }

    override fun addOnPageStartedListener(listener: (url: String) -> Unit) {
        onPageStartedListeners += listener
    }

    protected fun resetWebView() {
        cachedWebView = null
    }

    protected fun notifyOnPageFinished() {
        onPageFinishedListeners.forEach { it.invoke() }
    }

    protected fun notifyOnPageStarted(url: String) {
        onPageStartedListeners.forEach { it.invoke(url) }
    }

    protected fun notifyRenderProcessGone() {
        onWebViewDestroyed?.invoke()
    }

    fun pauseConnections() {
        cachedWebView?.evaluateJavascript("__pauseConnections__()") {}
    }

    fun resumeConnections() {
        cachedWebView?.evaluateJavascript("__resumeConnections__()") {}
    }
}
