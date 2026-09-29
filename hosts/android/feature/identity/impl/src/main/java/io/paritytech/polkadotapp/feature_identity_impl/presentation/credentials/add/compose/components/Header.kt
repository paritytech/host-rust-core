package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.models.CredentialsAddStep
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun Header(step: CredentialsAddStep) {
    Column {
        NovaText(
            text = stringResource(
                RCommon.string.identity_credentials_add_steps_counter,
                step.ordinal + 1,
                CredentialsAddStep.entries.size
            ),
            style = PolkadotTheme.typography.body.medium,
            color = PolkadotTheme.colors.fg.secondary
        )

        VerticalSpacer { small }

        NovaText(
            text = stringResource(
                when (step) {
                    CredentialsAddStep.ADD_HANDLE -> RCommon.string.identity_credentials_add_handle_title
                    CredentialsAddStep.ADD_PROOF -> RCommon.string.identity_credentials_add_proof_title
                }
            ),
            style = PolkadotTheme.typography.headline.small
        )
    }
}
