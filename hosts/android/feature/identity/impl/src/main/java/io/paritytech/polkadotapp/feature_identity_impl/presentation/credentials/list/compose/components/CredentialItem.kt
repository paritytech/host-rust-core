package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.compose.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.colors.LegacyNovaStableColors
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.*
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialState
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose.components.getPlatformName
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.models.CredentialUiModel
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun CredentialItem(
    item: CredentialUiModel,
    onItemAction: (CredentialUiModel) -> Unit
) {
    Row(
        modifier = Modifier
            .clickable { onItemAction(item) }
            .padding(vertical = PolkadotTheme.spacings.small),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HorizontalSpacer { mediumIncreased }

        CredentialIcon(
            icon = when (item.platform) {
                is IdentityCredentialPlatform.Discord -> NovaIcons.Discord
                is IdentityCredentialPlatform.Twitter -> NovaIcons.Twitter
                is IdentityCredentialPlatform.Github -> NovaIcons.Github
            },
            state = item.state
        )

        HorizontalSpacer { extraMedium }

        val platformName = item.platform.getPlatformName()

        NovaText(
            modifier = Modifier.weight(1f),
            text = platformName,
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.primary
        )

        CredentialState(
            platformName = platformName,
            state = item.state
        )

        HorizontalSpacer { small }
    }
}

@Composable
private fun CredentialIcon(
    icon: ImageVector,
    state: IdentityCredentialState
) {
    Surface(
        color = PolkadotTheme.colors.bg.surface.nested,
        shape = PolkadotTheme.shapes.medium,
        shadowElevation = 2.dp
    ) {
        Box(
            modifier = Modifier
                .padding(PolkadotTheme.spacings.tiny)
                .background(
                    when (state) {
                        IdentityCredentialState.Rejected,
                        is IdentityCredentialState.Confirmed -> Color.White
                        IdentityCredentialState.NotAdded,
                        IdentityCredentialState.Review -> Color.White.copy(0.3f)
                    },
                    PolkadotTheme.shapes.full
                )
                .padding(PolkadotTheme.spacings.tiny)
        ) {
            NovaIcon(
                modifier = Modifier.size(16.dp),
                imageVector = icon,
                tint = LegacyNovaStableColors.NeutralNeutral900
            )
        }
    }
}

@Composable
private fun CredentialState(
    platformName: String,
    state: IdentityCredentialState
) {
    Row(
        verticalAlignment = Alignment.CenterVertically
    ) {
        when (state) {
            is IdentityCredentialState.Confirmed -> {
                NovaText(
                    text = state.username,
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.primary
                )

                NovaIcon(
                    modifier = Modifier.padding(PolkadotTheme.spacings.tiny),
                    imageVector = NovaIcons.ArrowRight,
                    tint = PolkadotTheme.colors.fg.tertiary
                )
            }
            IdentityCredentialState.NotAdded -> {
                NovaText(
                    text = stringResource(
                        RCommon.string.identity_credentials_platform_add,
                        platformName
                    ),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.tertiary
                )

                NovaIcon(
                    modifier = Modifier.padding(PolkadotTheme.spacings.tiny),
                    imageVector = NovaIcons.ArrowRight,
                    tint = PolkadotTheme.colors.fg.tertiary
                )
            }
            IdentityCredentialState.Rejected -> {
                NovaText(
                    text = stringResource(RCommon.string.identity_credentials_platform_rejected),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.error
                )

                NovaIcon(
                    modifier = Modifier.padding(PolkadotTheme.spacings.tiny),
                    imageVector = NovaIcons.ArrowRight,
                    tint = PolkadotTheme.colors.fg.error
                )
            }
            IdentityCredentialState.Review -> {
                NovaText(
                    text = stringResource(RCommon.string.identity_credentials_platform_under_review),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.tertiary
                )

                NovaIcon(
                    modifier = Modifier.padding(PolkadotTheme.spacings.tiny),
                    imageVector = NovaIcons.Downloading,
                    tint = PolkadotTheme.colors.fg.tertiary
                )
            }
        }
    }
}
