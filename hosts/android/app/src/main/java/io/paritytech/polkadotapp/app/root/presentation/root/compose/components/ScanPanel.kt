package io.paritytech.polkadotapp.app.root.presentation.root.compose.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.compose.AddContactPanel
import io.paritytech.polkadotapp.feature_scan_impl.presentation.scanPanel.compose.EmbeddedQrScanner

@Composable
internal fun ScanPanel(
    onScanHandled: (navigate: (() -> Unit)?) -> Unit,
) {
    AddContactPanel(
        modifier = Modifier
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.small),
        scanner = { modifier ->
            EmbeddedQrScanner(
                modifier = modifier,
                onScanHandled = onScanHandled,
            )
        },
    )
}
