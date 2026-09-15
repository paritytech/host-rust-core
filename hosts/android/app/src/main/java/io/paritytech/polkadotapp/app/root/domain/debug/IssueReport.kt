package io.paritytech.polkadotapp.app.root.domain.debug

import java.io.File

data class IssueReport(
    val description: String,
    val logs: File,
    val screenshot: File,
)

fun interface IssueReportApi {
    suspend fun send(report: IssueReport): Result<Unit>
}
