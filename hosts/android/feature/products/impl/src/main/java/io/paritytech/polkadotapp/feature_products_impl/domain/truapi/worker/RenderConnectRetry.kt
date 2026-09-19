package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.retryWhen
import uniffi.truapi_server.ProductRuntimeException
import kotlin.time.Duration

/**
 * A worker's script is loaded before its client has opened the socket to the core, so a render
 * asked for in that window is refused as not connected. Such a refusal is retried; anything else
 * is a failure of the stream.
 */
internal fun <T> Flow<T>.retryWhileConnecting(attempts: Long, delay: Duration): Flow<T> =
    retryWhen { cause, attempt ->
        val connecting = cause is ProductRuntimeException.NotConnected && attempt < attempts
        if (connecting) delay(delay)
        connecting
    }
