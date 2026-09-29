package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose.components

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButton
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButtonSize
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.AutoAwesome
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.text.NovaTextField
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.models.CredentialsAddStep
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun AddHandleStep(
    platform: IdentityCredentialPlatform,
    onPasteAction: () -> Unit,
    onNextStepAction: () -> Unit,
    credential: String,
    onCredentialValueChanged: (String) -> Unit,
    onBackAction: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding()
            .imePadding()
    ) {
        Column {
            PolkadotTopBar(
                navigationAction = rememberTopBarAction(onBackAction),
                content = { Header(CredentialsAddStep.ADD_HANDLE) },
            )

            VerticalSpacer { small }

            Column(
                modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.large)
            ) {
                NovaText(
                    modifier = Modifier.fillMaxWidth(),
                    text = platform.getDescription(),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.secondary
                )

                VerticalSpacer { extraLarge }

                NovaTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = credential,
                    onValueChange = onCredentialValueChanged,
                    placeholder = {
                        NovaText(text = platform.getPlaceholder())
                    },
                    singleLine = true,
                    border = null,
                    containerColor = Color(0x1FFFFFFF)
                )

                VerticalSpacer { small }

                PolkadotButton(
                    onClick = onPasteAction,
                    style = PolkadotButtonStyle.secondary(),
                    size = PolkadotButtonSize.custom(
                        PaddingValues(
                            horizontal = PolkadotTheme.spacings.mediumIncreased,
                            vertical = 10.dp
                        )
                    ),
                    content = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
                        ) {
                            NovaIcon(imageVector = NovaIcons.AutoAwesome)
                            NovaText(text = stringResource(RCommon.string.common_paste))
                        }
                    }
                )
            }
        }

        PolkadotTextButton(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .padding(PolkadotTheme.spacings.large),
            text = stringResource(R.string.common_next),
            style = PolkadotButtonStyle.primary(),
            onClick = onNextStepAction
        )
    }
}

@Composable
private fun IdentityCredentialPlatform.getDescription() = stringResource(
    when (this) {
        is IdentityCredentialPlatform.Discord -> RCommon.string.identity_credentials_add_handle_discord_description
        is IdentityCredentialPlatform.Twitter -> RCommon.string.identity_credentials_add_handle_twitter_description
        is IdentityCredentialPlatform.Github -> RCommon.string.identity_credentials_add_handle_github_description
    }
)

@Composable
private fun IdentityCredentialPlatform.getPlaceholder() = stringResource(
    when (this) {
        is IdentityCredentialPlatform.Discord -> RCommon.string.identity_credentials_add_handle_discord_placeholder
        is IdentityCredentialPlatform.Twitter -> RCommon.string.identity_credentials_add_handle_twitter_placeholder
        is IdentityCredentialPlatform.Github -> RCommon.string.identity_credentials_add_handle_github_placeholder
    }
)

@Preview
@Composable
fun AddHandleStepPreview() {
    PolkadotTheme {
        PolkadotSurface {
            AddHandleStep(
                platform = IdentityCredentialPlatform.fromValue("Twitter", "polkadot")!!,
                onPasteAction = {},
                onNextStepAction = {},
                credential = "",
                onCredentialValueChanged = {},
                onBackAction = {}
            )
        }
    }
}
