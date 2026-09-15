package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.compose.EvidencePhotoCaptureScreen
import javax.inject.Inject

@AndroidEntryPoint
class EvidencePhotoCaptureFragment : BaseComposeFragment<EvidencePhotoCaptureViewModel>() {
    override val viewModel by viewModels<EvidencePhotoCaptureViewModel>()

    @Inject
    lateinit var timeFormatter: TimeFormatter

    @Composable
    override fun Screen() {
        CompositionLocalProvider(
            LocalTimeFormatter provides timeFormatter
        ) {
            EvidencePhotoCaptureScreen(viewModel)
        }
    }
}
