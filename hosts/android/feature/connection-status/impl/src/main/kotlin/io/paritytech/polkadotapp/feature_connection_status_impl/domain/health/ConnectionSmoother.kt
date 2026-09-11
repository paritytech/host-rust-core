package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.runningFold
import kotlinx.coroutines.flow.transformLatest
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.ExperimentalTime

/** Boundary state the smoother works on, decoupled from the substrate-sdk socket state. */
enum class RawConnectivity {
    Connected,
    Pending,
    Settled,
}

data class ConnectionSmoothingConfig(
    val stabilityWindow: Duration,
    val flapWindow: Duration,
    val flapDropThreshold: Int,
    val flapHold: Duration,
    val sustainedDisconnect: Duration,
) {
    companion object {
        val Default = ConnectionSmoothingConfig(
            stabilityWindow = 3.seconds,
            flapWindow = 30.seconds,
            flapDropThreshold = 2,
            flapHold = 5.seconds,
            sustainedDisconnect = 5.seconds,
        )
    }
}

/**
 * Hysteresis over the raw connectivity so reconnect storms read as a steady "connecting" rather than
 * flickering. Rising edges wait out a stability window (extended while flapping) before reporting
 * [ChainConnectionPresentation.Connected]; a settled disconnect waits out a cooldown before reporting
 * [ChainConnectionPresentation.Disconnected]. [timeProvider] is injectable so the time-based logic is
 * testable under virtual time.
 */
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalTime::class)
class ConnectionSmoother internal constructor(
    private val config: ConnectionSmoothingConfig,
    private val timeProvider: TimeProvider,
) {
    @Inject
    constructor(timeProvider: TimeProvider) : this(ConnectionSmoothingConfig.Default, timeProvider)

    fun smooth(source: Flow<RawConnectivity>): Flow<ChainConnectionPresentation> = flow {
        val drops = ArrayDeque<Long>()

        val transitions = source
            .runningFold(Transition(null, null)) { acc, state -> Transition(acc.current, state) }
            .drop(1)

        emitAll(
            transitions.transformLatest { (previous, current) ->
                val nowConnected = current == RawConnectivity.Connected
                val wasConnected = previous == RawConnectivity.Connected
                if (wasConnected && !nowConnected) recordDrop(drops)

                when {
                    nowConnected -> {
                        if (!wasConnected) {
                            // Rising edge: stay pending through a stability window (longer while
                            // flapping) so a reconnect storm reads as steady "connecting".
                            emit(ChainConnectionPresentation.Connecting)
                            delay(if (isFlapping(drops)) config.flapHold else config.stabilityWindow)
                        }
                        emit(ChainConnectionPresentation.Connected)
                    }

                    current == RawConnectivity.Settled -> {
                        emit(ChainConnectionPresentation.Connecting)
                        delay(config.sustainedDisconnect)
                        emit(ChainConnectionPresentation.Disconnected)
                    }

                    else -> emit(ChainConnectionPresentation.Connecting)
                }
            }.distinctUntilChanged(),
        )
    }

    private fun now(): Long = timeProvider.now().toEpochMilliseconds()

    private fun recordDrop(drops: ArrayDeque<Long>) {
        val now = now()
        purgeOld(drops, now)
        drops.addLast(now)
    }

    private fun isFlapping(drops: ArrayDeque<Long>): Boolean {
        purgeOld(drops, now())
        return drops.size >= config.flapDropThreshold
    }

    private fun purgeOld(drops: ArrayDeque<Long>, now: Long) {
        val cutoff = now - config.flapWindow.inWholeMilliseconds
        while (drops.isNotEmpty() && drops.first() < cutoff) drops.removeFirst()
    }

    private data class Transition(val previous: RawConnectivity?, val current: RawConnectivity?)
}
