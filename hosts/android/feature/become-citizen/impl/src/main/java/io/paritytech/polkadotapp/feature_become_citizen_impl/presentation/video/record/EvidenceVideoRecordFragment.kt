package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record.compose.EvidenceVideoRecordScreen
import javax.inject.Inject

@AndroidEntryPoint
class EvidenceVideoRecordFragment : BaseComposeFragment<EvidenceVideoRecordViewModel>() {
    override val viewModel by viewModels<EvidenceVideoRecordViewModel>()

    @Inject
    lateinit var timeFormatter: TimeFormatter

    @Composable
    override fun Screen() {
        CompositionLocalProvider(
            LocalTimeFormatter provides timeFormatter
        ) {
            EvidenceVideoRecordScreen(viewModel)
        }
    }
}
