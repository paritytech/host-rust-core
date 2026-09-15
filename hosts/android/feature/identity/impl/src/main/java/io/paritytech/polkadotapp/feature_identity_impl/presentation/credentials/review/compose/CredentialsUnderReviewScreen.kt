package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.review.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Report
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.review.CredentialsUnderReviewContract
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun CredentialsUnderReviewScreen(contract: CredentialsUnderReviewContract) {
    CredentialsUnderReviewScreenInternal(
        onAction = contract::actionClicked
    )
}

@Composable
private fun CredentialsUnderReviewScreenInternal(
    onAction: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(vertical = PolkadotTheme.spacings.large)
            .systemBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Column(
            modifier = Modifier.weight(0.25f),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            NovaText(
                modifier = Modifier.padding(horizontal = 44.dp),
                text = stringResource(RCommon.string.identity_credentials_review_title),
                style = PolkadotTheme.typography.headline.large,
                color = PolkadotTheme.colors.fg.primary,
                textAlign = TextAlign.Center
            )

            VerticalSpacer { extraMedium }

            NovaText(
                modifier = Modifier.padding(horizontal = 44.dp),
                text = stringResource(RCommon.string.identity_credentials_review_description),
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.tertiary,
                textAlign = TextAlign.Center
            )
        }

        Column(
            modifier = Modifier
                .weight(0.5f)
                .padding(horizontal = PolkadotTheme.spacings.large),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                NovaText(
                    text = stringResource(RCommon.string.become_citizen_tattoo_evidence_provided_review_action),
                    style = PolkadotTheme.typography.title.medium,
                    color = PolkadotTheme.colors.fg.secondary,
                    textAlign = TextAlign.Center
                )

                HorizontalSpacer { tiny }

                NovaIcon(
                    imageVector = NovaIcons.Report,
                    tint = PolkadotTheme.colors.fg.secondary
                )
            }
        }

        Box(
            modifier = Modifier.weight(0.25f)
        ) {
            PolkadotTextButton(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = PolkadotTheme.spacings.large),
                text = stringResource(RCommon.string.identity_credentials_review_action),
                onClick = onAction
            )
        }
    }
}

@Preview
@Composable
fun CredentialsUnderReviewScreenPreview() {
    PolkadotTheme {
        CredentialsUnderReviewScreenInternal(
            onAction = {}
        )
    }
}
