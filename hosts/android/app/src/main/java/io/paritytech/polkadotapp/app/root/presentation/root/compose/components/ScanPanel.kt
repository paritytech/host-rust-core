package io.paritytech.polkadotapp.app.root.presentation.root.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.topbar.PolkadotSearchFieldButton
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_scan_impl.presentation.scanPanel.compose.EmbeddedQrScanner
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun ScanPanel(
    onScanHandled: (navigate: (() -> Unit)?) -> Unit,
    onUsernameSearchClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.small),
    ) {
        PolkadotSurface(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f),
            shape = PolkadotTheme.shapes.extraLarge,
            color = PolkadotTheme.colors.bg.surface.nested,
        ) {
            EmbeddedQrScanner(
                modifier = Modifier.fillMaxSize(),
                onScanHandled = onScanHandled,
            )
        }

        VerticalSpacer { small }

        PolkadotSearchFieldButton(
            modifier = Modifier.fillMaxWidth(),
            placeholder = stringResource(RCommon.string.add_contact_search_placeholder),
            onClick = onUsernameSearchClick,
        )
    }
}
