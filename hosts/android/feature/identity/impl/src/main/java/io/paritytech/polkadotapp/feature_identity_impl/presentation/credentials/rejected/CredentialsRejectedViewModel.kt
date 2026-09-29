package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_identity_impl.IdentityRouter
import javax.inject.Inject

@HiltViewModel
class CredentialsRejectedViewModel @Inject constructor(
    private val router: IdentityRouter,
    private val payload: CredentialsRejectedPayload,
) : BaseViewModel(), CredentialsRejectedContract {
    override fun onActionClicked() {
        router.openAddCredentials(payload.platform)
    }
}
