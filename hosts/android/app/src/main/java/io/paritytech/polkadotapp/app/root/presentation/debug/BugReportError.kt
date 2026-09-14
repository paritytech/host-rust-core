package io.paritytech.polkadotapp.app.root.presentation.debug

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.app.root.domain.debug.DebugLogError
import io.paritytech.polkadotapp.common.presentation.ui.errors.PresentationThrowable
import io.paritytech.polkadotapp.common.R as RCommon

sealed class BugReportError(cause: Throwable) : PresentationThrowable(cause) {
    class CollectLogs(cause: Throwable) : BugReportError(cause)
    class SaveLogs(cause: Throwable) : BugReportError(cause)
    class OpenBrowser(cause: Throwable) : BugReportError(cause)

    @Composable
    override fun message(): String = stringResource(
        when (this) {
            is CollectLogs -> when (cause) {
                is DebugLogError.MissingLogs -> RCommon.string.debug_report_bug_missing_logs
                is DebugLogError.ArchiveTooLarge -> RCommon.string.debug_report_bug_logs_too_large
                else -> RCommon.string.debug_report_bug_collect_failed
            }
            is SaveLogs -> RCommon.string.debug_report_bug_save_failed
            is OpenBrowser -> RCommon.string.debug_report_bug_browser_failed
        }
    )
}
