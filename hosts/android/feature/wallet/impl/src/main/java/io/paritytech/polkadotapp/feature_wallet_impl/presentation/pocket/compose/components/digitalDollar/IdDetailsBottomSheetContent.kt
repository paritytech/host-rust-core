package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaBottomSheetSurface
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.icon.vectors.ContentCopy
import io.paritytech.polkadotapp.design.components.qr.QrCode
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.text.ensureAnnotatedString
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun IdDetailsBottomSheetContent(
    username: String,
    address: String,
    onClose: () -> Unit,
) {
    NovaBottomSheetSurface {
        Column(
            modifier = Modifier.padding(
                vertical = PolkadotTheme.spacings.mediumIncreased,
                horizontal = PolkadotTheme.spacings.mediumIncreased
            )
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                NovaText(
                    modifier = Modifier
                        .weight(1f),
                    text = stringResource(RCommon.string.pocket_id_share_scan_title),
                    style = PolkadotTheme.typography.headline.small
                )

                IconButton(onClick = onClose) {
                    NovaIcon(
                        imageVector = NovaIcons.Close
                    )
                }
            }

            VerticalSpacer { small }

            NovaText(
                text = stringResource(RCommon.string.pocket_id_share_subtitle),
                style = PolkadotTheme.typography.paragraph.large
            )

            VerticalSpacer { mediumIncreased }

            IdShareQrCard(username = username, address = address)
        }
    }
}

@Composable
internal fun IdShareQrCard(
    username: String,
    address: String,
    modifier: Modifier = Modifier
) {
    PolkadotSurface(
        modifier = modifier.fillMaxWidth(),
        shape = PolkadotTheme.shapes.large,
        color = PolkadotTheme.colors.bg.surface.nested
    ) {
        Column(
            modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            VerticalSpacer { large }

            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                NovaText(
                    modifier = Modifier.weight(1f, false),
                    text = username,
                    style = PolkadotTheme.typography.headline.small,
                    textAlign = TextAlign.Center
                )

                HorizontalSpacer { small }

                val clipboardManager = LocalClipboardManager.current
                NovaIcon(
                    modifier = Modifier
                        .clickable(
                            onClick = {
                                clipboardManager.setText(username.ensureAnnotatedString()) // TODO: move to viewmodel
                            }
                        ),
                    imageVector = NovaIcons.ContentCopy
                )
            }

            VerticalSpacer { extraLarge }

            QrCode(
                modifier = Modifier.size(214.dp),
                text = address
            )

            VerticalSpacer { large }
        }
    }
}

@Preview
@Composable
private fun IdDetailsBottomSheetContentPreview() {
    PolkadotTheme {
        IdDetailsBottomSheetContent(
            username = "aboba.77",
            address = "pizza",
            onClose = {},
        )
    }
}
