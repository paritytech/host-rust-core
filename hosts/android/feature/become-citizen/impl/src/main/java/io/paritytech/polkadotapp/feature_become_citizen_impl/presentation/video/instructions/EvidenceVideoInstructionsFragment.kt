package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.formatters.space.InformationSizeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.space.LocalInformationSizeFormatter
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions.compose.EvidenceVideoInstructionScreen
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import javax.inject.Inject

@AndroidEntryPoint
class EvidenceVideoInstructionsFragment : BaseComposeFragment<EvidenceVideoInstructionsViewModel>() {
    override val viewModel by viewModels<EvidenceVideoInstructionsViewModel>()

    @Inject
    lateinit var tokenAmountFormatter: TokenAmountFormatter

    @Inject
    lateinit var informationSizeFormatter: InformationSizeFormatter

    @Composable
    override fun Screen() {
        CompositionLocalProvider(
            LocalTokenAmountFormatter provides tokenAmountFormatter,
            LocalInformationSizeFormatter provides informationSizeFormatter
        ) {
            EvidenceVideoInstructionScreen(viewModel)
        }
    }
}
