package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import io.novasama.substrate_sdk_android.wsrpc.state.SocketStateMachine.State
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.flow.withIndex
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

private val OFFLINE_SETTLE: Duration = 1.seconds

internal fun rawConnectivity(socketStates: Flow<State?>, deviceOnline: Flow<Boolean>): Flow<RawConnectivity> =
    socketStates
        .combine(deviceOnline.settleLosses()) { state, online -> state.toRawConnectivity(online) }
        .distinctUntilChanged()

// A reconnecting socket reads as pending forever; with no network there is nothing to reconnect to.
internal fun State?.toRawConnectivity(deviceOnline: Boolean): RawConnectivity =
    if (deviceOnline) toSocketConnectivity() else RawConnectivity.Settled

// Only losing the network waits it out: a handover drops connectivity for a moment while every
// socket stays up. The first value is not a loss, so an offline start still draws immediately.
@OptIn(ExperimentalCoroutinesApi::class)
private fun Flow<Boolean>.settleLosses(): Flow<Boolean> = distinctUntilChanged()
    .withIndex()
    .transformLatest { (index, online) ->
        if (!online && index > 0) delay(OFFLINE_SETTLE)
        emit(online)
    }

private fun State?.toSocketConnectivity(): RawConnectivity = when (this) {
    is State.Connected -> RawConnectivity.Connected
    is State.Connecting, is State.WaitingForReconnect -> RawConnectivity.Pending
    null, is State.Disconnected, is State.Paused -> RawConnectivity.Settled
}
