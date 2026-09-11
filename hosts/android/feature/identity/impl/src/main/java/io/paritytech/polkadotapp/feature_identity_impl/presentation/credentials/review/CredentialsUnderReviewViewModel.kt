package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.review

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_identity_impl.IdentityRouter
import javax.inject.Inject

@HiltViewModel
class CredentialsUnderReviewViewModel @Inject constructor(
    private val router: IdentityRouter
) : BaseViewModel(), CredentialsUnderReviewContract {
    override fun actionClicked() {
        router.openMain()
    }
}
