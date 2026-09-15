package io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.PeerChannelConnectionState

interface GameDashboardTelemetryRepository {
    suspend fun sendRegistration(
        chain: Chain,
        localAccount: AccountId,
        usernameAccountId: AccountId,
        username: String?
    ): Result<Unit>

    suspend fun sendReporting(
        chain: Chain,
        localAccount: AccountId,
        rounds: List<List<PeerEntry>>
    ): Result<Unit>

    suspend fun sendEnd(
        chain: Chain,
        localAccount: AccountId,
        rounds: List<List<VerdictEntry>>
    ): Result<Unit>

    data class PeerEntry(val accountId: AccountId, val state: PeerChannelConnectionState)
    data class VerdictEntry(val accountId: AccountId, val verdict: Verdict)
    enum class Verdict { Person, NotPerson }
}
