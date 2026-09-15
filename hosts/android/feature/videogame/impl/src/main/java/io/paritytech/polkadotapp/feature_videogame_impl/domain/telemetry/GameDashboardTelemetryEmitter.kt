package io.paritytech.polkadotapp.feature_videogame_impl.domain.telemetry

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository.PeerEntry
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository.VerdictEntry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Owns the lifecycle of debug-dashboard telemetry: chain resolution, retry policy,
 * fire-and-forget scheduling, failure logging.
 *
 * The transport ([GameDashboardTelemetryRepository]) stays stateless and delivers a
 * single POST per call. This emitter is `@Singleton` and holds a long-lived
 * [SupervisorJob] so in-flight POSTs survive game-session teardown — particularly
 * `/end`, which is submitted from a screen that tears down shortly after.
 */
@Singleton
class GameDashboardTelemetryEmitter @Inject constructor(
    private val repository: GameDashboardTelemetryRepository,
    private val chainRegistry: ChainRegistry,
    dispatchers: CoroutineDispatchers,
) : CoroutineScope {
    override val coroutineContext = dispatchers.io + SupervisorJob()

    fun submitRegistration(
        localAccount: AccountId,
        usernameAccountId: AccountId,
        username: String?,
    ) = enqueue(LABEL_REGISTRATION) { chain ->
        repository.sendRegistration(chain, localAccount, usernameAccountId, username)
    }

    fun submitReporting(
        localAccount: AccountId,
        rounds: List<List<PeerEntry>>,
    ) = enqueue(LABEL_REPORTING) { chain ->
        repository.sendReporting(chain, localAccount, rounds)
    }

    fun submitEnd(
        localAccount: AccountId,
        rounds: List<List<VerdictEntry>>,
    ) = enqueue(LABEL_END) { chain ->
        repository.sendEnd(chain, localAccount, rounds)
    }

    private fun enqueue(label: String, send: suspend (chain: Chain) -> Result<Unit>) {
        launch {
            val chain = chainRegistry.peopleChain()
            deliver(label) { send(chain) }
        }
    }

    private suspend fun deliver(label: String, send: suspend () -> Result<Unit>) {
        RETRY_DELAYS.forEachIndexed { attempt, _ ->
            val error = send().exceptionOrNull() ?: return
            if (error !is GameDashboardTelemetryError.Transient) {
                logRejection(label, error)
                return
            }
            delay(RETRY_DELAYS[attempt])
        }
        // Final attempt after all delays.
        send().onFailure { logRejection(label, it, " after retries") }
    }

    private fun logRejection(label: String, error: Throwable, suffix: String = "") {
        val status = (error as? GameDashboardTelemetryError.NonRetryable)
            ?.let { " (status=${it.statusCode})" }
            .orEmpty()
        Timber.w(error, "Dashboard telemetry rejected at $label$status; dropping$suffix")
    }

    private companion object {
        const val LABEL_REGISTRATION = "registration"
        const val LABEL_REPORTING = "reporting"
        const val LABEL_END = "end"

        // Delays between successive attempts. Total attempts = size + 1 (one initial try
        // without delay, then one retry per element).
        val RETRY_DELAYS: List<Duration> = listOf(1.seconds, 2.seconds, 4.seconds)
    }
}
