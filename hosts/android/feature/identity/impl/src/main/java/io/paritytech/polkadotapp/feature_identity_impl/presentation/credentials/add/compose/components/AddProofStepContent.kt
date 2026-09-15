package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose.components

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.models.CredentialsAddStep
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun AddProofStep(
    platform: IdentityCredentialPlatform,
    credential: String,
    polkadotName: String,
    onCopyAction: () -> Unit,
    onOpenAction: () -> Unit,
    onSubmitAction: () -> Unit,
    isSubmissionInProgress: Boolean,
    onBackAction: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
        ) {
            PolkadotTopBar(
                navigationAction = rememberTopBarAction(onBackAction),
                content = { Header(CredentialsAddStep.ADD_PROOF) },
            )

            VerticalSpacer { small }

            Column(
                modifier = Modifier
                    .padding(horizontal = PolkadotTheme.spacings.large)
            ) {
                NovaText(
                    modifier = Modifier.fillMaxWidth(),
                    text = stringResource(
                        RCommon.string.identity_credentials_proof_description,
                        platform.getPlatformName()
                    ),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.secondary
                )

                PolkadotSurface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 56.dp),
                    color = Color(0x0FFFFFFF),
                    shape = PolkadotTheme.shapes.large,
                    border = BorderStroke(PolkadotTheme.borders.default, PolkadotTheme.colors.stroke.primary)
                ) {
                    Column {
                        UsernameSection(
                            credential = credential,
                            platform = platform
                        )

                        PolkadotSurface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(PolkadotTheme.spacings.tiny),
                            color = Color(0x1FFFFFFF),
                            shape = RoundedCornerShape(22.dp)
                        ) {
                            ProofSection(
                                polkadotName = polkadotName,
                                platform = platform,
                                onOpenAction = onOpenAction,
                                onCopyAction = onCopyAction
                            )
                        }
                    }
                }

                VerticalSpacer { extraLargeIncreased }
            }
        }

        PolkadotTextButton(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(PolkadotTheme.spacings.large)
                .fillMaxWidth(),
            text = stringResource(RCommon.string.identity_credentials_add_proof_action),
            style = PolkadotButtonStyle.primary(),
            onClick = onSubmitAction,
            loading = isSubmissionInProgress
        )
    }
}

@Composable
private fun ProofSection(
    polkadotName: String,
    platform: IdentityCredentialPlatform,
    onOpenAction: () -> Unit,
    onCopyAction: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.mediumIncreased)
    ) {
        ProofTitle()

        VerticalSpacer { small }

        NovaText(
            text = polkadotName,
            color = PolkadotTheme.colors.fg.primary,
            style = PolkadotTheme.typography.headline.small
        )

        VerticalSpacer { large }

        OpenButton(platform, onOpenAction)

        PolkadotTextButton(
            modifier = Modifier.fillMaxWidth(),
            text = stringResource(RCommon.string.common_copy),
            style = PolkadotButtonStyle.secondary(),
            onClick = onCopyAction
        )
    }
}

@Composable
private fun UsernameSection(
    credential: String,
    platform: IdentityCredentialPlatform
) {
    Column(
        modifier = Modifier
            .padding(
                horizontal = 20.dp,
                vertical = PolkadotTheme.spacings.large
            )
    ) {
        UsernameTitle()

        VerticalSpacer { small }

        NovaText(
            text = formatCredential(credential, platform),
            color = PolkadotTheme.colors.fg.primary,
            style = PolkadotTheme.typography.title.large,
        )
    }
}

@Composable
private fun OpenButton(
    platform: IdentityCredentialPlatform,
    onOpenAction: () -> Unit
) {
    when (platform) {
        is IdentityCredentialPlatform.Discord -> Unit
        is IdentityCredentialPlatform.Twitter,
        is IdentityCredentialPlatform.Github -> {
            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(
                    RCommon.string.identity_credentials_add_proof_open_action,
                    platform.getPlatformName()
                ),
                style = PolkadotButtonStyle.secondary(),
                onClick = onOpenAction
            )

            VerticalSpacer { small }
        }
    }
}

@Composable
private fun ProofTitle() {
    Row {
        NovaText(
            modifier = Modifier.weight(1f),
            text = stringResource(RCommon.string.identity_credentials_add_proof_second_step_title).uppercase(),
            color = PolkadotTheme.colors.fg.tertiary,
            style = PolkadotTheme.typography.title.medium,
        )
        NovaText(
            text = "2/2",
            color = PolkadotTheme.colors.fg.tertiary,
            style = PolkadotTheme.typography.title.medium,
        )
    }
}

@Composable
private fun UsernameTitle() {
    Row {
        NovaText(
            modifier = Modifier.weight(1f),
            text = stringResource(RCommon.string.identity_credentials_add_proof_first_step_title).uppercase(),
            color = PolkadotTheme.colors.fg.tertiary,
            style = PolkadotTheme.typography.title.medium,
        )
        NovaText(
            text = "1/2",
            color = PolkadotTheme.colors.fg.tertiary,
            style = PolkadotTheme.typography.title.medium,
        )
    }
}

private fun formatCredential(credential: String, platform: IdentityCredentialPlatform) = when (platform) {
    is IdentityCredentialPlatform.Discord -> "#$credential"
    is IdentityCredentialPlatform.Twitter -> "x.com/$credential"
    is IdentityCredentialPlatform.Github -> "github.com/$credential"
}

@Preview
@Composable
fun AddProofStepPreview() {
    PolkadotTheme {
        PolkadotSurface {
            AddProofStep(
                platform = IdentityCredentialPlatform.fromValue("Twitter", "aRolf")!!,
                credential = "aRolf",
                polkadotName = "best-dot-name.dot",
                onCopyAction = {},
                onOpenAction = {},
                onSubmitAction = {},
                isSubmissionInProgress = false,
                onBackAction = {}
            )
        }
    }
}
