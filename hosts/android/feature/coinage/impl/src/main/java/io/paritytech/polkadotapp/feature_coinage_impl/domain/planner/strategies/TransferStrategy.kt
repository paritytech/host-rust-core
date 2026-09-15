package io.paritytech.polkadotapp.feature_coinage_impl.domain.planner.strategies

import io.paritytech.polkadotapp.common.utils.progressStallReport.StalenessReportCollector
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.PlannedMemoEntry
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageHandoffCommit

sealed interface TransferStrategy {
    /**
     * Executes the transfer, owning every mutation (allocation, marking coins spent, marking vouchers used) via
     * [io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransaction]. Returns the memo entries
     * describing the coins handed to the recipient, built from the coins actually allocated here.
     */
    context(diagnostics: StalenessReportCollector)
    suspend fun run(): Result<PreparedTransfer>
}

/**
 * [handoffCommit] must be committed once the keys in [entries] are durably on their way — until then the
 * coins are reserved but recoverable, and a relaunch returns them.
 */
data class PreparedTransfer(
    val entries: List<PlannedMemoEntry>,
    val handoffCommit: CoinageHandoffCommit,
)
