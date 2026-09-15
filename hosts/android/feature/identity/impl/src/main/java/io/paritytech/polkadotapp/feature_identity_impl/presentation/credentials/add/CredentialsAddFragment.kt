package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add

import androidx.compose.runtime.Composable
import androidx.core.os.bundleOf
import androidx.fragment.app.viewModels
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose.CredentialsAddScreen
import kotlin.getValue

class CredentialsAddFragment : BaseComposeFragment<CredentialsAddViewModel>() {
    override val viewModel: CredentialsAddViewModel by viewModels()

    companion object {
        private const val PAYLOAD_KEY = "195a3e32-2470-49f3-bc1f-9485647642f4"

        fun getBundle(payload: CredentialsAddPayload) = bundleOf(PAYLOAD_KEY to payload)
    }

    @Composable
    override fun Screen() = CredentialsAddScreen(viewModel)
}
