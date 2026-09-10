package io.paritytech.polkadotapp.feature_wallet_impl.presentation.enterAmount.compose.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction

@Composable
internal fun EnterAmountToolbar(onBackClick: () -> Unit) {
    PolkadotTopBar(
        modifier = Modifier.fillMaxWidth(),
        navigationAction = rememberTopBarAction(
            action = onBackClick,
            icon = NovaIcons.Close
        ),
        title = stringResource(id = R.string.send_enter_amount_title),
        titleAlignment = TopBarTitleAlignment.Center,
    )
}
