package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add

import io.paritytech.polkadotapp.common.presentation.clipboard.ClipboardService
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.*
import io.paritytech.polkadotapp.feature_identity_impl.IdentityRouter
import io.paritytech.polkadotapp.feature_identity_impl.domain.interactor.CredentialsAddInteractor
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.models.CredentialsAddStep
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

class CredentialsAddViewModel @Inject constructor(
    private val payload: CredentialsAddPayload,
    private val router: IdentityRouter,
    private val clipboardService: ClipboardService,
    private val interactor: CredentialsAddInteractor,
) : BaseViewModel(), CredentialsAddContract {
    override val platform = MutableStateFlow(payload.platform)

    override val step = MutableStateFlow(CredentialsAddStep.ADD_HANDLE)
    override val credential = MutableStateFlow("")

    override val polkadotName = flow {
        emit(interactor.getClaimedUsername())
    }.stateInBackground(SharingStarted.Eagerly, "")

    override val credentialSubmissionProgress = MutableStateFlow(false)

    override fun backClicked() {
        when (step.value) {
            CredentialsAddStep.ADD_HANDLE -> router.back()
            CredentialsAddStep.ADD_PROOF -> step.value = CredentialsAddStep.ADD_HANDLE
        }
    }

    override fun pasteCredentialClicked() {
        clipboardService.getPrimaryClip()?.let { credential.value = it }
    }

    override fun continueClicked() {
        when (step.value) {
            CredentialsAddStep.ADD_HANDLE -> {
                if (credential.value.isNotEmpty()) {
                    step.value = CredentialsAddStep.ADD_PROOF
                }
            }
            CredentialsAddStep.ADD_PROOF -> launch {
                credentialSubmissionProgress.enable()

                interactor.submitCredentials(payload.platform, credential.value)
                    .onSuccess { router.openMain() }
                    .onFailure { showError(it) }

                credentialSubmissionProgress.disable()
            }
        }
    }

    override fun onCredentialChanged(value: String) {
        credential.value = value
    }

    override fun onCopyPolkadotNameClicked() {
        clipboardService.setPrimaryClip(polkadotName.value)
    }
}
