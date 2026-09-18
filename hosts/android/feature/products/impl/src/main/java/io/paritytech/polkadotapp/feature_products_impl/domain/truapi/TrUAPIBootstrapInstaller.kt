package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import javax.inject.Inject

/**
 * Registers a product's bootstrap script to run at document start, for the app WebView and the
 * hidden worker one alike.
 *
 * The support check belongs here rather than at either call site: taken after the execution is open,
 * a WebView without the feature throws from inside the attach callback and leaves a live loopback
 * listener that then blocks every re-attach.
 */
class TrUAPIBootstrapInstaller @Inject constructor() {
    fun installerFor(webView: WebView, origins: Set<String>): (bootstrap: String) -> Unit {
        check(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            "WebView lacks DOCUMENT_START_SCRIPT; cannot run a TrUAPI product"
        }

        return { bootstrap -> WebViewCompat.addDocumentStartJavaScript(webView, bootstrap, origins) }
    }
}
