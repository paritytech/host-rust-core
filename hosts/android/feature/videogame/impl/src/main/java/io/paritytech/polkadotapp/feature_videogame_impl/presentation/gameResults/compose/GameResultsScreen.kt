package io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults.compose

import android.webkit.WebView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults.GameResultsContract

@Composable
fun GameResultsScreen(contract: GameResultsContract) {
    // Always registered to swallow the system back press — when `showTopBar`
    // is off, JS owns dismissal via `flow.complete`.
    BackHandler {
        if (contract.showTopBar) contract.onBackPressed()
    }

    GameResultsScreenInternal(
        webView = contract.webView,
        showTopBar = contract.showTopBar,
        onCloseClick = contract::onCloseClick
    )
}

@Composable
private fun GameResultsScreenInternal(
    webView: WebView,
    showTopBar: Boolean,
    onCloseClick: () -> Unit
) {
    PolkadotSurface(color = PolkadotTheme.colors.bg.surface.main) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding(),
            verticalArrangement = Arrangement.Top
        ) {
            if (showTopBar) {
                PolkadotTopBar(
                    navigationAction = rememberTopBarAction(
                        action = onCloseClick,
                        icon = NovaIcons.Close
                    ),
                )
            }

            PolkadotSurface(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                color = PolkadotTheme.colors.bg.surface.container
            ) {
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { webView }
                )
            }
        }
    }
}
