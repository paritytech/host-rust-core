package io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitSpa.compose

import android.webkit.WebView
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButton
import io.paritytech.polkadotapp.design.components.progress.NovaCircularProgressIndicator
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitSpa.Web3SummitSpaUiState
import io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitSpa.Web3SummitSpaViewModel
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun Web3SummitSpaScreen(viewModel: Web3SummitSpaViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val webView by viewModel.webView.collectAsStateWithLifecycle()

    Web3SummitSpaScreenInternal(
        state = state,
        webView = webView,
        onSkipClick = viewModel::onSkipClick,
        onStartUsingAppClick = viewModel::onStartUsingAppClick,
    )
}

@Composable
private fun Web3SummitSpaScreenInternal(
    state: Web3SummitSpaUiState,
    webView: WebView?,
    onSkipClick: () -> Unit,
    onStartUsingAppClick: () -> Unit,
) {
    PolkadotSurface(color = PolkadotTheme.colors.bg.surface.main) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding(),
        ) {
            if (webView != null) {
                AndroidView(
                    factory = { webView },
                    modifier = Modifier.fillMaxSize(),
                )
            }

            when {
                state.isAttendanceConfirmed -> Web3SummitBottomButton(
                    onClick = onStartUsingAppClick,
                    isUsernameEstablishing = state.showUsernameEstablishing,
                    readyTextRes = RCommon.string.w3s_start_using_app,
                    preparingTextRes = RCommon.string.w3s_start_using_app_preparing,
                )

                state.showSkipButton -> Web3SummitBottomButton(
                    onClick = onSkipClick,
                    isUsernameEstablishing = state.showUsernameEstablishing,
                    readyTextRes = RCommon.string.w3s_debug_skip,
                    preparingTextRes = RCommon.string.w3s_start_using_app_preparing,
                )
            }
        }
    }
}

@Composable
private fun BoxScope.Web3SummitBottomButton(
    onClick: () -> Unit,
    isUsernameEstablishing: Boolean,
    @StringRes readyTextRes: Int,
    @StringRes preparingTextRes: Int,
) {
    PolkadotButton(
        onClick = onClick,
        enabled = !isUsernameEstablishing,
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.large),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            if (isUsernameEstablishing) {
                NovaCircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    color = LocalContentColor.current,
                    strokeWidth = PolkadotTheme.borders.medium
                )
                HorizontalSpacer { small }
            }

            val textRes = if (isUsernameEstablishing) preparingTextRes else readyTextRes
            NovaText(text = stringResource(textRes))
        }
    }
}
