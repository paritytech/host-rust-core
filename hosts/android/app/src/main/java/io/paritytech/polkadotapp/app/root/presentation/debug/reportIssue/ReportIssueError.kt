package io.paritytech.polkadotapp.app.root.presentation.debug.reportIssue

import io.paritytech.polkadotapp.common.presentation.ui.errors.PresentationError
import io.paritytech.polkadotapp.common.presentation.ui.errors.StringResPresentationError
import io.paritytech.polkadotapp.common.R as RCommon

class ReportIssueError(cause: Throwable) : Exception(cause),
    PresentationError by StringResPresentationError(RCommon.string.debug_report_failed)
