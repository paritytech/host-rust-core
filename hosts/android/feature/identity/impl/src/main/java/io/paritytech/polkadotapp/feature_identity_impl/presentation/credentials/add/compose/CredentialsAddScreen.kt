package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.utils.browseUrl
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.CredentialsAddContract
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose.components.*
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.models.CredentialsAddStep

@Composable
fun CredentialsAddScreen(contract: CredentialsAddContract) {
    BackHandler { contract.backClicked() }

    CredentialsAddScreenInternal(
        platform = contract.platform.collectAsStateWithLifecycle().value,
        step = contract.step.collectAsStateWithLifecycle().value,
        credential = contract.credential.collectAsStateWithLifecycle().value,
        polkadotName = contract.polkadotName.collectAsStateWithLifecycle().value,
        onBackAction = contract::backClicked,
        onPasteAction = contract::pasteCredentialClicked,
        onContinueClicked = contract::continueClicked,
        onCredentialValueChanged = contract::onCredentialChanged,
        onCopyPolkadotNameAction = contract::onCopyPolkadotNameClicked,
        isSubmissionInProgress = contract.credentialSubmissionProgress.collectAsStateWithLifecycle().value
    )
}

@Composable
private fun CredentialsAddScreenInternal(
    platform: IdentityCredentialPlatform,
    step: CredentialsAddStep,
    credential: String,
    polkadotName: String,
    onBackAction: () -> Unit,
    onPasteAction: () -> Unit,
    onContinueClicked: () -> Unit,
    onCredentialValueChanged: (String) -> Unit,
    onCopyPolkadotNameAction: () -> Unit,
    isSubmissionInProgress: Boolean
) {
    when (step) {
        CredentialsAddStep.ADD_HANDLE -> AddHandleStep(
            platform = platform,
            onPasteAction = onPasteAction,
            onNextStepAction = onContinueClicked,
            credential = credential,
            onCredentialValueChanged = onCredentialValueChanged,
            onBackAction = onBackAction
        )

        CredentialsAddStep.ADD_PROOF -> {
            val context = LocalContext.current

            AddProofStep(
                platform = platform,
                credential = credential,
                polkadotName = polkadotName,
                onCopyAction = onCopyPolkadotNameAction,
                onOpenAction = {
                    onCopyPolkadotNameAction()
                    platform.getSettingsUrl(credential)?.let(context::browseUrl)
                },
                onSubmitAction = onContinueClicked,
                isSubmissionInProgress = isSubmissionInProgress,
                onBackAction = onBackAction
            )
        }
    }
}

@Preview
@Composable
private fun CredentialsAddScreenPreview() {
    PolkadotTheme {
        CredentialsAddScreenInternal(
            platform = IdentityCredentialPlatform.Discord("username#1234"),
            step = CredentialsAddStep.ADD_HANDLE,
            credential = "username",
            polkadotName = "best-dot-name.dot",
            onBackAction = {},
            onPasteAction = {},
            onContinueClicked = {},
            onCredentialValueChanged = {},
            onCopyPolkadotNameAction = {},
            isSubmissionInProgress = false
        )
    }
}
