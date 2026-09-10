package io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults

import android.webkit.WebView

interface GameResultsContract {
    val webView: WebView

    /**
     * Whether the host should render its top bar (back arrow + title).
     * Off in production — the JS ceremony owns dismissal via the
     * `Done` button on `DoneScreen` (which fires `flow.complete`).
     * On in debug-menu / simulator paths so testers can always escape.
     */
    val showTopBar: Boolean

    fun onCloseClick()
    fun onBackPressed()
}
