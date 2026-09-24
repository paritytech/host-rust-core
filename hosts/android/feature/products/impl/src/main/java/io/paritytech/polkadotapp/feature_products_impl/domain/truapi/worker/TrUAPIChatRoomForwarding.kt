package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.toCoreChatRoom
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import timber.log.Timber
import kotlin.time.Duration.Companion.seconds

internal class TrUAPIChatRoomForwarding(
    private val productId: ProductId,
    private val execution: TrUAPIProductExecution,
    private val chatMessaging: ProductChatMessaging,
) {
    fun start(scope: CoroutineScope): Job = scope.launch {
        repeat(REBIND_POLL_ATTEMPTS) { attempt ->
            chatMessaging.subscribeChatRooms()
                .onEach { rooms -> execution.notifyChatRoomsChanged(rooms.map { it.toCoreChatRoom() }) }
                // A bad room must not kill the scope.
                .catch { failure ->
                    if (failure is CancellationException) throw failure
                    Timber.w(
                        failure,
                        "TrUAPI chat room forwarding for %s failed (attempt %d/%d); will re-resolve",
                        productId.value,
                        attempt + 1,
                        REBIND_POLL_ATTEMPTS,
                    )
                }
                .launchIn(this)
                .join()
            if (attempt < REBIND_POLL_ATTEMPTS - 1) delay(REBIND_POLL_INTERVAL)
        }
        Timber.w(
            "TrUAPI chat room forwarding for %s gave up: no chat surface bound after %d attempts",
            productId.value,
            REBIND_POLL_ATTEMPTS,
        )
    }

    private companion object {
        val REBIND_POLL_INTERVAL = 5.seconds
        const val REBIND_POLL_ATTEMPTS = 12
    }
}
