package io.paritytech.polkadotapp.app.root.presentation.debug.reportIssue

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.app.root.presentation.debug.reportIssue.compose.ReportIssueScreen
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeBottomSheet

@AndroidEntryPoint
class ReportIssueBottomSheet : BaseComposeBottomSheet<ReportIssueViewModel>() {
    override val viewModel: ReportIssueViewModel by viewModels()

    @Composable
    override fun Screen() = ReportIssueScreen(viewModel)
}
