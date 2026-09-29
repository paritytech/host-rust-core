package io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository.PeerEntry
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository.VerdictEntry

/**
 * Used on the production environment, where game-dashboard telemetry must not be sent. Every call is
 * a successful no-op so callers need no environment branching.
 */
internal object NoOpGameDashboardTelemetryRepository : GameDashboardTelemetryRepository {
    override suspend fun sendRegistration(
        chain: Chain,
        localAccount: AccountId,
        usernameAccountId: AccountId,
        username: String?,
    ): Result<Unit> = Result.success(Unit)

    override suspend fun sendReporting(
        chain: Chain,
        localAccount: AccountId,
        rounds: List<List<PeerEntry>>,
    ): Result<Unit> = Result.success(Unit)

    override suspend fun sendEnd(
        chain: Chain,
        localAccount: AccountId,
        rounds: List<List<VerdictEntry>>,
    ): Result<Unit> = Result.success(Unit)
}
