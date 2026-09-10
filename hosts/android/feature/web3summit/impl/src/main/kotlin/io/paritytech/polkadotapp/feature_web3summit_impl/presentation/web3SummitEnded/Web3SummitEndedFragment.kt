package io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitEnded

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitEnded.compose.Web3SummitEndedScreen

@AndroidEntryPoint
class Web3SummitEndedFragment : BaseComposeFragment<Web3SummitEndedViewModel>() {
    override val viewModel: Web3SummitEndedViewModel by viewModels()

    @Composable
    override fun Screen() = Web3SummitEndedScreen(viewModel)
}
