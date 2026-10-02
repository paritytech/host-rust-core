package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.retryWhen
import uniffi.truapi.ProductRuntimeException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * A worker's script is loaded before its client has opened the socket to the core, so a render
 * asked for in that window is refused as not connected. Such a refusal is retried; anything else
 * is a failure of the stream.
 */
internal fun <T> Flow<T>.retryWhileConnecting(
    attempts: Long = CONNECT_ATTEMPTS,
    retryDelay: Duration = CONNECT_RETRY_DELAY,
): Flow<T> = retryWhen { cause, attempt ->
    val connecting = cause is ProductRuntimeException.NotConnected && attempt < attempts
    if (connecting) delay(retryDelay)
    connecting
}

/** Doubling from [BACKOFF_BASE] to [MAX_BACKOFF]: a slow surface is picked up at once, a broken one is not asked on a loop. */
internal fun reopenBackoff(attempt: Long): Duration =
    minOf(BACKOFF_BASE * (1 shl attempt.coerceAtMost(MAX_BACKOFF_SHIFT).toInt()), MAX_BACKOFF)

private const val CONNECT_ATTEMPTS = 40L
private val CONNECT_RETRY_DELAY = 250.milliseconds

private val BACKOFF_BASE = 1.seconds
private val MAX_BACKOFF = 30.seconds
private const val MAX_BACKOFF_SHIFT = 5L
