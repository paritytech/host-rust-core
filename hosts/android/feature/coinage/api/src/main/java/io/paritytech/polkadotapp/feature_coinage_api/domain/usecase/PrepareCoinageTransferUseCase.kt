package io.paritytech.polkadotapp.feature_coinage_api.domain.usecase

import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.progressStallReport.StalenessReportCollector
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.TransferMemo
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.TransferPlan
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageHandoffCommit
import java.math.BigDecimal

interface PrepareCoinageTransferUseCase {
    suspend fun preparePlan(amount: BigDecimal): Result<TransferPlan>

    /**
     * Builds the memo and reserves the coins it names. The reservation is provisional: commit
     * [PreparedTransferMemo.handoffCommit] once the memo is durably on its way to the recipient, or leave it
     * and a relaunch returns the coins.
     *
     * Reports its progress into [diagnostics]; callers with no UI attached pass
     * [StalenessReportCollector.NoOp].
     */
    context(diagnostics: StalenessReportCollector)
    suspend fun prepareMemo(plan: TransferPlan): Result<PreparedTransferMemo>
}

data class PreparedTransferMemo(
    val memo: TransferMemo,
    val handoffCommit: CoinageHandoffCommit,
)

context(diagnostics: StalenessReportCollector)
suspend fun PrepareCoinageTransferUseCase.prepareMemo(amount: BigDecimal) = preparePlan(amount).flatMap { prepareMemo(it) }
