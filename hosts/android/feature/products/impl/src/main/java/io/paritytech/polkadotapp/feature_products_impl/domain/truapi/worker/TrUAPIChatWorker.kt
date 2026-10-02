package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import io.parity.truapi.TrUAPIHostRuntime
import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId
import io.paritytech.polkadotapp.feature_products_api.model.JsUiEvent
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_api.model.ProductChatIdParameter
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.renderer.toJsWidget
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorker
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.retryWhen
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
            workers.executionState(productId)
                .map { (it as? WorkerExecutionState.Running)?.execution }
                .distinctUntilChanged()
                .collectLatest { execution ->
                    if (execution == null) return@collectLatest
                    coroutineScope { TrUAPIChatRoomForwarding(productId, execution, chatMessaging).start(this) }
                }
        }
    }

    override suspend fun onUserMessage(roomId: ProductChatIdParameter?, text: String): Result<Unit> {
        if (roomId == null) return roomlessFailure("message")
        val outcome = runCatching {
            val execution = awaitRunningExecution()
            execution.publishChatAction(
                HostChatActionSubscribeItem(
                    roomId = roomId.value,
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
        roomId: ProductChatIdParameter?,
        messageId: ChatMessageId,
        messageType: String,
        messageData: DataByteArray,
    ): Flow<Result<JsWidget>> {
        if (roomId == null) return flowOf(roomlessFailure("render"))
        return channelFlow {
            val outcome = runCatching {
                workers.executionState(productId)
                    .distinctUntilChanged()
                    .flatMapLatest { state ->
                        when (state) {
                            // Reported, not thrown: a later execution must still be able to draw.
                            is WorkerExecutionState.Failed ->
                                flowOf(Result.failure(ExecutionUnavailableException(state.reason)))
                            null -> emptyFlow()
                            is WorkerExecutionState.Running -> {
                                reopeningChatRender(
                                    state.execution,
                                    roomId.value,
                                    messageId,
                                    messageType,
                                    messageData.value,
                                )
                            }
                        }
                    }
                    .collect { send(it) }
            }
            outcome.exceptionOrNull()?.let { failure ->
                if (failure is CancellationException) throw failure
                trySend(Result.failure(failure))
            }
        }.conflate()
    }

    override fun dispatchEvent(event: JsUiEvent) {
        val roomId = event.roomId
        if (roomId == null) {
            Timber.w("TrUAPI chat dispatchEvent for %s/%s dropped: no room id", productId.value, event.messageId)
            return
        }
        val execution = workers.currentExecution(productId)
        if (execution == null) {
            Timber.w("TrUAPI chat dispatchEvent for %s/%s dropped: no running execution", productId.value, event.messageId)
            return
        }
        val context = RenderContext.ChatMessage(roomId = roomId.value, messageId = event.messageId, messageType = event.messageType)
        runCatching {
            execution.publishRendererAction(
                HostRendererActionSubscribeItem(context, event.actionId, event.eventType.toActionPayload()),
            )
        }.logFailure("truapi.renderer.action '${event.actionId}' for ${productId.value}")
    }

    private fun <T> roomlessFailure(what: String): Result<T> {
        val reason = "TrUAPI chat $what for ${productId.value} carries no room id"
        Timber.w(reason)
        return Result.failure(IllegalArgumentException(reason))
    }

    private suspend fun runningExecution(): TrUAPIProductExecution =
        when (val state = workers.executionState(productId).filterNotNull().first()) {
            is WorkerExecutionState.Running -> state.execution
            is WorkerExecutionState.Failed -> throw ExecutionUnavailableException(state.reason)
        }

    private suspend fun awaitRunningExecution(): TrUAPIProductExecution =
        withTimeoutOrNull(TrUAPIWorkerSupervisor.EXECUTION_WAIT_TIMEOUT) { runningExecution() }
            ?: throw IllegalStateException(
                "TrUAPI worker for ${productId.value} did not report a running execution in time",
            )

    private fun reopeningChatRender(
        execution: TrUAPIProductExecution,
        roomId: String,
        messageId: ChatMessageId,
        messageType: String,
        payload: ByteArray,
    ): Flow<Result<JsWidget>> {
        val context = RenderContext.ChatMessage(roomId = roomId, messageId = messageId, messageType = messageType)
        var everDrew = false
        var drewThisAttempt = false
        var lastFailure: Throwable? = null

        // Wrapped, so a retry re-asks the execution for a render instead of re-collecting a spent one.
        return flow {
            emitAll(
                execution.render(ProductRendererRenderRequest(context, payload))
                    .retryWhileConnecting()
                    // Above the retry: a conversion failure is a stream failure, not a silent drop.
                    .map { it.toJsWidget() }
                    .onStart { drewThisAttempt = false }
                    .onEach {
                        drewThisAttempt = true
                        everDrew = true
                    }
                    .onCompletion { cause -> if (cause == null && !drewThisAttempt) throw StreamDrewNothing() },
            )
        }
            .retryWhen { cause, attempt ->
                if (cause is CancellationException) return@retryWhen false
                if (cause !is StreamDrewNothing) lastFailure = cause
                val reopening = attempt < RENDER_ATTEMPTS - 1
                if (reopening) {
                    if (cause is StreamDrewNothing) {
                        Timber.d("TrUAPI chat render for %s/%s drew nothing (attempt %d); reopening", productId.value, messageId, attempt + 1)
                    } else {
                        Timber.w(cause, "TrUAPI chat render for %s/%s failed (attempt %d); reopening", productId.value, messageId, attempt + 1)
                    }
                    delay(REOPEN_DELAY)
                }
                reopening
            }
            .map { Result.success(it) }
            .catch { cause ->
                // The execution went away, not the render: end quietly and let the replacement draw.
                if (cause is CancellationException) return@catch
                if (!everDrew) {
                    emit(
                        Result.failure(
                            IllegalStateException(
                                "TrUAPI render for ${productId.value} message '$messageId' never drew after $RENDER_ATTEMPTS attempts",
                                lastFailure ?: cause,
                            ),
                        ),
                    )
                }
            }
    }

    private class StreamDrewNothing : Exception("the render stream ended without drawing")

    private fun JsUiEvent.Type.toActionPayload(): ByteArray = when (this) {
        JsUiEvent.Type.ButtonClick -> ByteArray(0)
        is JsUiEvent.Type.InputFieldValueChange -> newValue.toByteArray(Charsets.UTF_8)
    }

    private class ExecutionUnavailableException(cause: Throwable) : Exception(cause.message, cause)

    private companion object {
        const val NATIVE_PEER = "native"

        const val RENDER_ATTEMPTS = 3
        val REOPEN_DELAY = 500.milliseconds
    }
}
