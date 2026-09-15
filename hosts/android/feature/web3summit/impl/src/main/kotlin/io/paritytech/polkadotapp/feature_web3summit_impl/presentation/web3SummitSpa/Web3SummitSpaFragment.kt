package io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitSpa

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitSpa.compose.Web3SummitSpaScreen

@AndroidEntryPoint
class Web3SummitSpaFragment : BaseComposeFragment<Web3SummitSpaViewModel>() {
    override val viewModel: Web3SummitSpaViewModel by viewModels()

    @Composable
    override fun Screen() = Web3SummitSpaScreen(viewModel)

    override fun onPause() {
        super.onPause()
        viewModel.pauseConnections()
    }

    override fun onResume() {
        super.onResume()
        viewModel.resumeConnections()
    }
}
