package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected

import androidx.compose.runtime.Composable
import androidx.core.os.bundleOf
import androidx.fragment.app.viewModels
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected.compose.CredentialsRejectedScreen

class CredentialsRejectedFragment : BaseComposeFragment<CredentialsRejectedViewModel>() {
    override val viewModel: CredentialsRejectedViewModel by viewModels()

    companion object {
        const val PAYLOAD_KEY = "CredentialsRejectedFragment.Payload"

        fun getBundle(payload: CredentialsRejectedPayload) = bundleOf(PAYLOAD_KEY to payload)
    }

    @Composable
    override fun Screen() = CredentialsRejectedScreen(viewModel)
}
