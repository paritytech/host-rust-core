package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add

import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.models.CredentialsAddStep
import kotlinx.coroutines.flow.StateFlow

interface CredentialsAddContract {
    val platform: StateFlow<IdentityCredentialPlatform>

    val step: StateFlow<CredentialsAddStep>
    val credential: StateFlow<String>

    val polkadotName: StateFlow<String>

    val credentialSubmissionProgress: StateFlow<Boolean>

    fun backClicked()

    fun pasteCredentialClicked()
    fun continueClicked()

    fun onCredentialChanged(value: String)
    fun onCopyPolkadotNameClicked()
}
