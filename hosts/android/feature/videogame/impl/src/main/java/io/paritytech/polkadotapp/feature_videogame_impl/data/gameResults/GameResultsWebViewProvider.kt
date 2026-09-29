package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsResolver
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_dotns_api.presentation.DotNsServingHostResolver
import io.paritytech.polkadotapp.feature_dotns_api.presentation.DotNsWebViewClient
import io.paritytech.polkadotapp.feature_videogame_impl.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import timber.log.Timber
import javax.inject.Inject

/**
 * Builds a [WebView] hosting the game-results web app. [create] wires the WebView up but
 * does not navigate; [load] resolves the URL ([GameResultsUrlProvider]) and navigates. The
 * split keeps WebView construction synchronous (callers need the view immediately) while
 * the async URL resolution stays off the construction path. Caller disposes via
 * [Bundle.destroy].
 */
class GameResultsWebViewProvider @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val urlProvider: GameResultsUrlProvider,
    private val dotNsResolver: DotNsResolver,
    private val dotNsTldProvider: DotNsTldProvider,
    private val servingHostResolver: DotNsServingHostResolver,
) {
    /**
     * @param pageFinished Flips to true on `WebViewClient.onPageFinished`.
     *   `window.setGameResults(...)` must not be called before this — the
     *   JS app buffers calls until React mounts.
     * @param mainFrameError Flips to true on `WebViewClient.onReceivedError`
     *   for a main-frame request. The preloader uses it as the retry trigger;
     *   the value resets on `onPageStarted`.
     */
    data class Bundle(
        val webView: WebView,
        val sender: GameResultsJsSender,
        val bridge: GameResultsJsBridge,
        val pageFinished: StateFlow<Boolean>,
        val mainFrameError: StateFlow<Boolean>,
    ) {
        fun destroy() {
            webView.removeJavascriptInterface(JS_INTERFACE_NAME)
            webView.stopLoading()
            webView.destroy()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    fun create(): Bundle {
        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        val pageFinished = MutableStateFlow(false)
        val mainFrameError = MutableStateFlow(false)
        val bridge = GameResultsJsBridge()
        val webView = WebView(context).apply {
            with(settings) {
                javaScriptEnabled = true
                domStorageEnabled = true
                // Off: the bundle is served over the .dot origin via DotNsWebViewClient, never file://
                // (a file:// origin taints the prize-draw <canvas>).
                allowFileAccess = false
                allowContentAccess = false
                mediaPlaybackRequiresUserGesture = false
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            }
            webViewClient = LoadStateClient(
                pageFinished,
                mainFrameError,
                dotNsResolver,
                dotNsTldProvider,
                servingHostResolver,
            )
            webChromeClient = ConsoleLoggingChromeClient()
            addJavascriptInterface(bridge, JS_INTERFACE_NAME)
        }
        return Bundle(
            webView = webView,
            sender = GameResultsJsSender(webView),
            bridge = bridge,
            pageFinished = pageFinished.asStateFlow(),
            mainFrameError = mainFrameError.asStateFlow(),
        )
    }

    /** Resolves the URL (DotNs → Remote Config → bundled) and navigates. Call once per bundle. */
    suspend fun load(bundle: Bundle) {
        val url = urlProvider.resolveUrl()
        bundle.webView.loadUrl(url)
    }

    private class LoadStateClient(
        private val pageFinished: MutableStateFlow<Boolean>,
        private val mainFrameError: MutableStateFlow<Boolean>,
        dotNsResolver: DotNsResolver,
        dotNsTldProvider: DotNsTldProvider,
        servingHostResolver: DotNsServingHostResolver,
    ) : DotNsWebViewClient(dotNsResolver, dotNsTldProvider, servingHostResolver) {
        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
            super.onPageStarted(view, url, favicon)
            pageFinished.value = false
            mainFrameError.value = false
        }

        override fun onPageFinished(view: WebView?, url: String?) {
            super.onPageFinished(view, url)
            pageFinished.value = true
        }

        override fun onReceivedError(
            view: WebView?,
            request: WebResourceRequest?,
            error: WebResourceError?,
        ) {
            super.onReceivedError(view, request, error)
            if (request?.isForMainFrame != true) return
            Timber.w(
                "[GameResults] onReceivedError mainFrame code=${error?.errorCode} desc=${error?.description} url=${request.url}"
            )
            mainFrameError.value = true
        }
    }

    /** Pipes JS `console.*` into Timber under tag `GameResultsJS`. */
    private class ConsoleLoggingChromeClient : WebChromeClient() {
        override fun onConsoleMessage(message: ConsoleMessage?): Boolean {
            if (message == null) return false
            val tag = "GameResultsJS"
            val text = "${message.message()} (@${message.sourceId()}:${message.lineNumber()})"
            when (message.messageLevel()) {
                ConsoleMessage.MessageLevel.ERROR -> Timber.tag(tag).e(text)
                ConsoleMessage.MessageLevel.WARNING -> Timber.tag(tag).w(text)
                ConsoleMessage.MessageLevel.LOG,
                ConsoleMessage.MessageLevel.DEBUG,
                ConsoleMessage.MessageLevel.TIP,
                null -> Timber.tag(tag).d(text)
            }
            return true
        }
    }

    private companion object {
        const val JS_INTERFACE_NAME = "gameResults"
    }
}
