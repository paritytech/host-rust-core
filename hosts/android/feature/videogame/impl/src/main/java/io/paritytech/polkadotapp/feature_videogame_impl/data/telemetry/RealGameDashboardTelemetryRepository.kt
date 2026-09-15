package io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.util.addressOf
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.mapError
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository.PeerEntry
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository.Verdict
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository.VerdictEntry
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.model.VideoGameEndDashboardRequest
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.model.VideoGameRegistrationDashboardRequest
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.model.VideoGameReportingDashboardRequest
import io.paritytech.polkadotapp.feature_videogame_impl.domain.telemetry.GameDashboardTelemetryError
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.PeerChannelConnectionState
import kotlinx.coroutines.withContext
import retrofit2.HttpException
import java.io.IOException
import javax.inject.Inject

internal class RealGameDashboardTelemetryRepository @Inject constructor(
    private val api: GameDashboardApi,
    private val dispatchers: CoroutineDispatchers,
) : GameDashboardTelemetryRepository {
    override suspend fun sendRegistration(
        chain: Chain,
        localAccount: AccountId,
        usernameAccountId: AccountId,
        username: String?,
    ): Result<Unit> = invoke {
        val request = VideoGameRegistrationDashboardRequest(
            who = chain.accountSlug(localAccount),
            usernameAccountId = chain.addressOf(usernameAccountId),
            username = username,
            timestamp = currentTimestampMs()
        )
        api.registration(request)
    }

    override suspend fun sendReporting(
        chain: Chain,
        localAccount: AccountId,
        rounds: List<List<PeerEntry>>,
    ): Result<Unit> = invoke {
        val request = VideoGameReportingDashboardRequest(
            who = chain.accountSlug(localAccount),
            peers = rounds.mapNested { entry ->
                VideoGameReportingDashboardRequest.Peer(
                    id = chain.accountSlug(entry.accountId),
                    state = entry.state.toDashboardState()
                )
            },
            timestamp = currentTimestampMs()
        )
        api.reporting(request)
    }

    override suspend fun sendEnd(
        chain: Chain,
        localAccount: AccountId,
        rounds: List<List<VerdictEntry>>,
    ): Result<Unit> = invoke {
        val request = VideoGameEndDashboardRequest(
            who = chain.accountSlug(localAccount),
            reports = rounds.mapNested { entry ->
                VideoGameEndDashboardRequest.Report(
                    id = chain.accountSlug(entry.accountId),
                    verdict = entry.verdict.wireValue
                )
            },
            timestamp = currentTimestampMs()
        )
        api.end(request)
    }

    private suspend fun invoke(block: suspend () -> Unit): Result<Unit> =
        withContext(dispatchers.io) {
            runCatching { block() }.mapError { it.toTelemetryError() }
        }

    private fun Throwable.toTelemetryError(): GameDashboardTelemetryError = when (this) {
        is HttpException -> if (code() == HTTP_TOO_MANY_REQUESTS || code() in HTTP_SERVER_ERROR_RANGE) {
            GameDashboardTelemetryError.Transient(this)
        } else {
            GameDashboardTelemetryError.NonRetryable(code(), this)
        }
        is IOException -> GameDashboardTelemetryError.Transient(this)
        else -> GameDashboardTelemetryError.NonRetryable(statusCode = 0, cause = this)
    }

    private fun PeerChannelConnectionState.toDashboardState(): String = when (this) {
        PeerChannelConnectionState.Connected -> "connected"
        PeerChannelConnectionState.Failed -> "failed"
        PeerChannelConnectionState.New,
        PeerChannelConnectionState.Connecting,
        PeerChannelConnectionState.Disconnected,
        PeerChannelConnectionState.Closed -> "disconnected"
    }

    private fun Chain.accountSlug(accountId: AccountId): String = "account:${addressOf(accountId)}"

    private fun currentTimestampMs(): Long = System.currentTimeMillis()

    private companion object {
        const val HTTP_TOO_MANY_REQUESTS = 429
        val HTTP_SERVER_ERROR_RANGE = 500..599
    }
}

private inline fun <T, R> List<List<T>>.mapNested(transform: (T) -> R): List<List<R>> =
    map { it.map(transform) }

private val Verdict.wireValue: String
    get() = when (this) {
        Verdict.Person -> "person"
        Verdict.NotPerson -> "notperson"
    }
