package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction

@Composable
internal fun MediaEvidenceTopBar(
    modifier: Modifier = Modifier,
    title: String,
    subtitle: String,
    onClose: () -> Unit,
) {
    PolkadotTopBar(
        modifier = modifier,
        navigationAction = rememberTopBarAction(
            action = onClose,
            icon = NovaIcons.Close,
        ),
        title = title,
        subtitle = subtitle,
        titleAlignment = TopBarTitleAlignment.Center,
    )
}
