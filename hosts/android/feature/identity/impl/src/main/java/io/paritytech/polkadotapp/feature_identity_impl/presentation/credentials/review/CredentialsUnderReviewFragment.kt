package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.review

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.review.compose.CredentialsUnderReviewScreen

class CredentialsUnderReviewFragment : BaseComposeFragment<CredentialsUnderReviewViewModel>() {
    override val viewModel: CredentialsUnderReviewViewModel by viewModels()

    @Composable
    override fun Screen() = CredentialsUnderReviewScreen(viewModel)
}
