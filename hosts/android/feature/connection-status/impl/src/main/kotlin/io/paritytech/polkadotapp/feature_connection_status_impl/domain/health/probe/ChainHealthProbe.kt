package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import kotlinx.coroutines.flow.Flow
import kotlin.time.Duration

/**
 * Shared per-chain inputs handed to every probe. Best/finalized flows are already shared upstream so
 * multiple probes reading them do not open duplicate subscriptions. [chain] exposes per-chain config
 * (e.g. `additional`) so a probe can read its own overrides.
 */
data class ChainMetricContext(
    val chain: Chain,
    val bestBlockNumber: Flow<Int>,
    val finalizedBlockNumber: Flow<Int>,
    val expectedBlockTime: Duration,
    // Requests currently pending on the socket, as stable identities (Sendable has no id, so tracked
    // by referential identity).
    val pendingRequests: Flow<Set<Any>>,
)

/**
 * The extensibility seam: one probe per health metric. Bind a new probe with `@Binds @IntoSet` and it
 * contributes to both the ring score (via `min`) and the details popover with no further wiring.
 */
interface ChainHealthProbe {
    fun observe(context: ChainMetricContext): Flow<ChainMetricReading>
}
