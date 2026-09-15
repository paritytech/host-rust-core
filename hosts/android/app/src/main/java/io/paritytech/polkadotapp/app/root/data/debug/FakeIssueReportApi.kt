package io.paritytech.polkadotapp.app.root.data.debug

import io.paritytech.polkadotapp.app.root.domain.debug.IssueReport
import io.paritytech.polkadotapp.app.root.domain.debug.IssueReportApi
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds

class FakeIssueReportApi @Inject constructor(
    private val dispatchers: CoroutineDispatchers,
) : IssueReportApi {
    override suspend fun send(report: IssueReport): Result<Unit> = withContext(dispatchers.io) {
        runCancellableCatching {
            require(report.description.isNotBlank())
            check(report.logs.length() > 0 && report.screenshot.length() > 0)
            delay(1.seconds)
        }
    }
}
