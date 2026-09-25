package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import io.parity.truapi.TrUAPIHostRuntime
import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId
import io.paritytech.polkadotapp.feature_products_api.model.JsUiEvent
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.renderer.toJsWidget
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorker
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import uniffi.truapi.ChatActionPayload
import uniffi.truapi.ChatMessageContent
import uniffi.truapi.HostChatActionSubscribeItem
import uniffi.truapi.HostRendererActionSubscribeItem
import uniffi.truapi.ProductRendererRenderRequest
import uniffi.truapi.RenderContext
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

class TrUAPIChatWorker(
    private val productId: ProductId,
    private val runtime: TrUAPIHostRuntime,
    private val workers: TrUAPIWorkerSupervisor,
    private val chatMessaging: ProductChatMessaging,
    private val scope: CoroutineScope,
) : ProductWorker {
    init {
        val workerJob = scope.coroutineContext.job
        runtime.acquireWorker(productId.value)
        workerJob.invokeOnCompletion {
            runCatching { runtime.releaseWorker(productId.value) }
                .onFailure { Timber.w(it, "TrUAPI releaseWorker failed for %s", productId.value) }
        }
        scope.launch {
            // Forwarding follows the executions: a failed boot ends this one, the next boot gets a new one.
            workers.executionState(productId)
                .map { (it as? WorkerExecutionState.Running)?.execution }
                .distinctUntilChanged()
                .collectLatest { execution ->
                    if (execution == null) return@collectLatest
                    coroutineScope { TrUAPIChatRoomForwarding(productId, execution, chatMessaging).start(this) }
                }
        }
    }

    override suspend fun onUserMessage(roomId: String?, text: String): Result<Unit> {
        val outcome = runCatching {
            val execution = awaitRunningExecution()
            execution.publishChatAction(
                HostChatActionSubscribeItem(
                    roomId = roomId.orDefaultChat(),
                    peer = NATIVE_PEER,
                    payload = ChatActionPayload.MessagePosted(ChatMessageContent.Text(text)),
                ),
            )
        }
        outcome.exceptionOrNull()?.let { if (it is CancellationException) throw it }
        return outcome.logFailure("truapi.chat.action for ${productId.value}")
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    override fun renderMessage(
        roomId: String?,
        messageId: ChatMessageId,
        messageType: String,
        messageData: DataByteArray,
    ): Flow<Result<JsWidget>> {
        return channelFlow {
            val outcome = runCatching {
                // Rendering follows the executions: one dying mid-render is redrawn by the next.
                workers.executionState(productId)
                    .map { state ->
                        if (state is WorkerExecutionState.Failed) throw ExecutionUnavailableException(state.reason)
                        (state as? WorkerExecutionState.Running)?.execution
                    }
                    .distinctUntilChanged()
                    .flatMapLatest { execution ->
                        if (execution == null) {
                            emptyFlow()
                        } else {
                            reopeningChatRender(
                                execution,
                                roomId.orDefaultChat(),
                                messageId,
                                messageType,
                                messageData.value,
                            )
                        }
                    }
                    .collect { send(it) }
            }
            outcome.exceptionOrNull()?.let { failure ->
                if (failure is CancellationException) throw failure
                // trySend: a throw here would crash the process, not just this cell.
                trySend(Result.failure(failure))
            }
        }.buffer(Channel.UNLIMITED)
    }

    override fun dispatchEvent(event: JsUiEvent) {
        val roomId = event.roomId.orDefaultChat()
        val execution = workers.currentExecution(productId)
        if (execution == null) {
            Timber.w("TrUAPI chat dispatchEvent for %s/%s dropped: no running execution", productId.value, event.messageId)
            return
        }
        val context = RenderContext.ChatMessage(roomId = roomId, messageId = event.messageId, messageType = event.messageType)
        runCatching {
            execution.publishRendererAction(
                HostRendererActionSubscribeItem(context, event.actionId, event.eventType.toActionPayload()),
            )
        }.logFailure("truapi.renderer.action '${event.actionId}' for ${productId.value}")
    }

    // The core addresses a product's default chat by the empty room id, as iOS does.
    private fun String?.orDefaultChat(): String = this ?: ""

    private suspend fun runningExecution(): TrUAPIProductExecution =
        when (val state = workers.executionState(productId).filterNotNull().first()) {
            is WorkerExecutionState.Running -> state.execution
            is WorkerExecutionState.Failed -> throw ExecutionUnavailableException(state.reason)
        }

    private suspend fun awaitRunningExecution(): TrUAPIProductExecution =
        withTimeoutOrNull(EXECUTION_WAIT_TIMEOUT) { runningExecution() }
            ?: throw IllegalStateException(
                "TrUAPI worker for ${productId.value} did not report a running execution within $EXECUTION_WAIT_TIMEOUT",
            )

    private fun reopeningChatRender(
        execution: TrUAPIProductExecution,
        roomId: String,
        messageId: ChatMessageId,
        messageType: String,
        payload: ByteArray,
    ): Flow<Result<JsWidget>> = flow {
        val context = RenderContext.ChatMessage(roomId = roomId, messageId = messageId, messageType = messageType)
        var everDrew = false
        var lastFailure: Throwable? = null

        for (attempt in 0 until RENDER_ATTEMPTS) {
            var drewThisAttempt = false
            val outcome = runCatching {
                execution.render(ProductRendererRenderRequest(context, payload))
                    .retryWhileConnecting(CONNECT_ATTEMPTS, CONNECT_RETRY_DELAY)
                    .collect { node ->
                        drewThisAttempt = true
                        everDrew = true
                        val widget = node.toJsWidget()
                        runCatching { emit(Result.success(widget)) }.onFailure { throw DownstreamEmitFailure(it) }
                    }
            }

            val failure = outcome.exceptionOrNull()
            if (failure is DownstreamEmitFailure) throw failure.original
            // Only the collector's own cancellation ends the render; the execution's death is one more failed attempt.
            if (failure is CancellationException && !currentCoroutineContext().isActive) throw failure
            if (failure == null && drewThisAttempt) break

            if (failure != null) {
                lastFailure = failure
                Timber.w(failure, "TrUAPI chat render for %s/%s failed (attempt %d); reopening", productId.value, messageId, attempt + 1)
            } else {
                Timber.d("TrUAPI chat render for %s/%s ended without drawing (attempt %d); reopening", productId.value, messageId, attempt + 1)
            }
            if (attempt < RENDER_ATTEMPTS - 1) delay(REOPEN_DELAY)
        }

        if (!everDrew) {
            emit(
                Result.failure(
                    IllegalStateException(
                        "TrUAPI render for ${productId.value} message '$messageId' never drew after $RENDER_ATTEMPTS attempts",
                        lastFailure,
                    ),
                ),
            )
        }
    }

    private class DownstreamEmitFailure(val original: Throwable) : Exception(original)

    private fun JsUiEvent.Type.toActionPayload(): ByteArray = when (this) {
        JsUiEvent.Type.ButtonClick -> ByteArray(0)
        is JsUiEvent.Type.InputFieldValueChange -> newValue.toByteArray(Charsets.UTF_8)
    }

    private class ExecutionUnavailableException(cause: Throwable) : Exception(cause.message, cause)

    private companion object {
        const val NATIVE_PEER = "native"

        val EXECUTION_WAIT_TIMEOUT = TrUAPIWorkerSupervisor.READY_TIMEOUT + 30.seconds

        const val RENDER_ATTEMPTS = 3
        val REOPEN_DELAY = 500.milliseconds

        const val CONNECT_ATTEMPTS = 40L
        val CONNECT_RETRY_DELAY = 250.milliseconds
    }
}
