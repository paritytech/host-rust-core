package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import io.parity.truapi.TrUAPIHostRuntime
import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId
import io.paritytech.polkadotapp.feature_products_api.model.JsUiEvent
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.FakeChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatRoom
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.ROOM_HOST
import io.paritytech.polkadotapp.test_shared.any
import io.paritytech.polkadotapp.test_shared.argThat
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import uniffi.truapi.ChatActionPayload
import uniffi.truapi.ChatMessageContent
import uniffi.truapi.HostChatActionSubscribeItem
import uniffi.truapi.HostRendererActionSubscribeItem
import uniffi.truapi.ProductRendererRenderRequest
import uniffi.truapi.RenderContext
import uniffi.truapi.RendererNode
import uniffi.truapi_server.ProductRuntimeException
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

class TrUAPIChatWorkerTest {
    private val productId = ProductId.fromStoredValue("chat.dot")
    private val roomId = "room-1"
    private val messageId: ChatMessageId = "msg-1"
    private val messageType = "custom.widget"
    private val messageData = DataByteArray.empty()

    private fun TestScope.worker(
        runtime: TrUAPIHostRuntime = mock(),
        workers: TrUAPIWorkerSupervisor = mock(),
        chatMessaging: ProductChatMessaging = FakeChatMessaging(),
        scope: CoroutineScope = CoroutineScope(StandardTestDispatcher(testScheduler)),
    ): TrUAPIChatWorker = TrUAPIChatWorker(productId, runtime, workers, chatMessaging, scope)

    private fun runningWorkers(execution: TrUAPIProductExecution): TrUAPIWorkerSupervisor {
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(flowOf(WorkerExecutionState.Running(execution)))
        return workers
    }

    @Test
    fun `a stream that draws renders once, against the room and message it was given`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        whenever(execution.render(any())).thenReturn(flowOf(RendererNode.Nil))
        val worker = worker(workers = runningWorkers(execution))

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(listOf(Result.success(JsWidget.Spacer())), results)
        var captured: ProductRendererRenderRequest? = null
        verify(execution, times(1)).render(argThat { captured = it; true })
        assertEquals(
            RenderContext.ChatMessage(roomId = roomId, messageId = messageId, messageType = messageType),
            requireNotNull(captured).context,
        )
    }

    @Test
    fun `a Failed execution state yields a failure without retrying`() = runTest {
        val boom = IllegalStateException("boot failed")
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(flowOf(WorkerExecutionState.Failed(boom)))
        val worker = worker(workers = workers)

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(1, results.size)
        val failure = results.single().exceptionOrNull()
        assertSame(boom, failure?.cause)
    }

    @Test
    fun `a Failed execution state whose cause is a TimeoutCancellationException still yields a failure value`() = runTest {
        val timeoutCause = try {
            withTimeout(1.milliseconds) { awaitCancellation() }
            error("unreachable: withTimeout should have thrown")
        } catch (e: TimeoutCancellationException) {
            e
        }
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(flowOf(WorkerExecutionState.Failed(timeoutCause)))
        val worker = worker(workers = workers)

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(1, results.size)
        val failure = results.single().exceptionOrNull()
        assertFalse("the value that reaches the collector must not itself be a cancellation", failure is CancellationException)
        assertSame(timeoutCause, failure?.cause)
    }

    @Test
    fun `a stream that ends without drawing is reopened`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        whenever(execution.render(any())).thenReturn(emptyFlow(), flowOf(RendererNode.Nil))
        val worker = worker(workers = runningWorkers(execution))

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(listOf(Result.success(JsWidget.Spacer())), results)
        verify(execution, times(2)).render(any())
    }

    @Test
    fun `a stream that fails outright is reopened`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        whenever(execution.render(any())).thenReturn(flow { throw IllegalStateException("boom") }, flowOf(RendererNode.Nil))
        val worker = worker(workers = runningWorkers(execution))

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(listOf(Result.success(JsWidget.Spacer())), results)
        verify(execution, times(2)).render(any())
    }

    @Test
    fun `a stream that fails after drawing keeps the drawn node and reopens without emitting a failure`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        val firstAttempt = flow<RendererNode> {
            emit(RendererNode.Nil)
            throw IllegalStateException("boom")
        }
        whenever(execution.render(any())).thenReturn(firstAttempt, flowOf(RendererNode.Nil))
        val worker = worker(workers = runningWorkers(execution))

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(listOf(Result.success(JsWidget.Spacer()), Result.success(JsWidget.Spacer())), results)
        verify(execution, times(2)).render(any())
    }

    @Test
    fun `render attempts exhausted by repeated failures carry the last cause`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        val boom1 = IllegalStateException("boom1")
        val boom2 = IllegalStateException("boom2")
        val boom3 = IllegalStateException("boom3")
        whenever(execution.render(any())).thenReturn(
            flow { throw boom1 },
            flow { throw boom2 },
            flow { throw boom3 },
        )
        val worker = worker(workers = runningWorkers(execution))

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        verify(execution, times(3)).render(any())
        assertEquals(1, results.size)
        assertSame(boom3, results.single().exceptionOrNull()?.cause)
    }

    @Test
    fun `a NotConnected retry does not consume a render attempt`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        var collected = 0
        val flakyThenDraws = flow<RendererNode> {
            collected++
            if (collected == 1) throw ProductRuntimeException.NotConnected()
            emit(RendererNode.Nil)
        }
        whenever(execution.render(any())).thenReturn(flakyThenDraws)
        val worker = worker(workers = runningWorkers(execution))

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(listOf(Result.success(JsWidget.Spacer())), results)
        assertEquals(2, collected)
        verify(execution, times(1)).render(any())
    }

    @Test
    fun `a disposed worker stops retrying instead of reopening`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        whenever(execution.render(any())).thenReturn(flow { awaitCancellation() })
        val states = MutableStateFlow<WorkerExecutionState?>(WorkerExecutionState.Running(execution))
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(states)
        val worker = worker(workers = workers, scope = CoroutineScope(StandardTestDispatcher(testScheduler)))

        val results = mutableListOf<Result<JsWidget>>()
        val collector = launch {
            worker.renderMessage(roomId, messageId, messageType, messageData).collect { results += it }
        }
        advanceUntilIdle()
        verify(execution, times(1)).render(any())

        // Disposal as the supervisor reports it: the product has no execution any more.
        states.value = null
        advanceUntilIdle()

        assertTrue(results.isEmpty())
        verify(execution, times(1)).render(any())

        collector.cancel()
    }

    @Test
    fun `a render on a worker whose scope is already cancelled still draws`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        whenever(execution.render(any())).thenReturn(flowOf(RendererNode.Nil))
        val workerScope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val worker = worker(workers = runningWorkers(execution), scope = workerScope)

        workerScope.cancel()
        advanceUntilIdle()

        val results = worker.renderMessage(roomId, messageId, messageType, messageData).toList()

        assertEquals(listOf(Result.success(JsWidget.Spacer())), results)
        verify(execution, times(1)).render(any())
    }

    @Test
    fun `a render whose execution dies before drawing is redrawn on the replacement execution`() = runTest {
        val dying: TrUAPIProductExecution = mock()
        val replacement: TrUAPIProductExecution = mock()
        whenever(dying.render(any())).thenReturn(flow { throw CancellationException("execution disposed") })
        whenever(replacement.render(any())).thenReturn(flowOf(RendererNode.Nil))
        val states = MutableStateFlow<WorkerExecutionState?>(WorkerExecutionState.Running(dying))
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(states)
        val worker = worker(workers = workers, scope = CoroutineScope(StandardTestDispatcher(testScheduler)))

        val results = mutableListOf<Result<JsWidget>>()
        val collector = launch {
            worker.renderMessage(roomId, messageId, messageType, messageData).collect { results += it }
        }
        advanceUntilIdle()

        assertTrue("the dying execution must not end the cell's flow", collector.isActive)

        states.value = WorkerExecutionState.Running(replacement)
        advanceUntilIdle()

        assertEquals(Result.success(JsWidget.Spacer()), results.lastOrNull())
        verify(replacement, times(1)).render(any())

        collector.cancel()
    }

    @Test
    fun `cancelling the collector stops the render instead of leaking it`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        val replacement: TrUAPIProductExecution = mock()
        var rendering = false
        whenever(execution.render(any())).thenReturn(
            flow {
                rendering = true
                try {
                    awaitCancellation()
                } finally {
                    rendering = false
                }
            },
        )
        val states = MutableStateFlow<WorkerExecutionState?>(WorkerExecutionState.Running(execution))
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(states)
        val worker = worker(workers = workers, scope = CoroutineScope(StandardTestDispatcher(testScheduler)))

        val collector = launch {
            worker.renderMessage(roomId, messageId, messageType, messageData).collect { }
        }
        advanceUntilIdle()
        assertTrue(rendering)

        collector.cancel()
        advanceUntilIdle()

        assertFalse("the render must not outlive its collector", rendering)
        states.value = WorkerExecutionState.Running(replacement)
        advanceUntilIdle()
        verify(replacement, never()).render(any())
    }

    @Test
    fun `dispatchEvent publishes a renderer action addressed by RenderContext ChatMessage`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.currentExecution(productId)).thenReturn(execution)
        whenever(workers.executionState(productId)).thenReturn(emptyFlow())
        val worker = worker(workers = workers)

        worker.dispatchEvent(
            JsUiEvent(messageId, messageType, actionId = "onTap", eventType = JsUiEvent.Type.ButtonClick, roomId = roomId),
        )
        worker.dispatchEvent(
            JsUiEvent(
                messageId,
                messageType,
                actionId = "onChange",
                eventType = JsUiEvent.Type.InputFieldValueChange("hi"),
                roomId = roomId,
            ),
        )

        val captured = mutableListOf<HostRendererActionSubscribeItem>()
        verify(execution, times(2)).publishRendererAction(argThat { captured += it; true })
        assertEquals(RenderContext.ChatMessage(roomId, messageId, messageType), captured[0].context)
        assertEquals("onTap", captured[0].actionId)
        assertTrue(captured[0].payload.isEmpty())
        assertEquals("hi", captured[1].payload.toString(Charsets.UTF_8))
    }

    @Test
    fun `onUserMessage publishes a chat action with peer native`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        val worker = worker(workers = runningWorkers(execution))

        val result = worker.onUserMessage(roomId, "hello")

        assertTrue(result.isSuccess)
        var captured: HostChatActionSubscribeItem? = null
        verify(execution).publishChatAction(argThat { captured = it; true })
        val item = requireNotNull(captured)
        assertEquals(roomId, item.roomId)
        assertEquals("native", item.peer)
        assertEquals(ChatActionPayload.MessagePosted(ChatMessageContent.Text("hello")), item.payload)
    }

    @Test
    fun `a null room is the default chat and reaches the core as an empty room id`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        val worker = worker(workers = runningWorkers(execution))

        val result = worker.onUserMessage(null, "hello")

        assertTrue(result.isSuccess)
        var captured: HostChatActionSubscribeItem? = null
        verify(execution).publishChatAction(argThat { captured = it; true })
        assertEquals("", requireNotNull(captured).roomId)
    }

    @Test
    fun `onUserMessage propagates a genuine cancellation instead of returning a Result`() = runTest {
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(flow { awaitCancellation() })
        val worker = worker(workers = workers)

        var result: Result<Unit>? = null
        val caller = launch {
            result = worker.onUserMessage(roomId, "hello")
        }
        runCurrent()

        caller.cancel()
        advanceUntilIdle()

        assertTrue(caller.isCancelled)
        assertNull("a swallowed cancellation would have let onUserMessage return a Result", result)
    }

    @Test
    fun `forwarding still starts after a slow boot, past the old 30s execution-wait bound`() = runTest {
        val execution: TrUAPIProductExecution = mock()
        val rooms = MutableSharedFlow<List<ProductChatRoom>>(extraBufferCapacity = 1)
        val chatMessaging = FakeChatMessaging(rooms = rooms)
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(
            flow {
                delay(45.seconds)
                emit(WorkerExecutionState.Running(execution))
            },
        )
        val workerScope = CoroutineScope(StandardTestDispatcher(testScheduler))

        worker(workers = workers, chatMessaging = chatMessaging, scope = workerScope)
        advanceUntilIdle()

        rooms.tryEmit(listOf(ProductChatRoom(roomId, ROOM_HOST)))
        advanceUntilIdle()

        verify(execution, times(1)).notifyChatRoomsChanged(any())
    }

    @Test
    fun `forwarding starts on the execution that follows a failed boot, and moves to a replacement`() = runTest {
        val first: TrUAPIProductExecution = mock()
        val replacement: TrUAPIProductExecution = mock()
        val rooms = MutableSharedFlow<List<ProductChatRoom>>()
        val chatMessaging = FakeChatMessaging(rooms = rooms)
        val states = MutableStateFlow<WorkerExecutionState?>(WorkerExecutionState.Failed(IllegalStateException("boot failed")))
        val workers: TrUAPIWorkerSupervisor = mock()
        whenever(workers.executionState(productId)).thenReturn(states)

        worker(workers = workers, chatMessaging = chatMessaging, scope = CoroutineScope(StandardTestDispatcher(testScheduler)))
        advanceUntilIdle()

        states.value = WorkerExecutionState.Running(first)
        advanceUntilIdle()
        rooms.emit(listOf(ProductChatRoom(roomId, ROOM_HOST)))
        advanceUntilIdle()
        verify(first, times(1)).notifyChatRoomsChanged(any())

        states.value = WorkerExecutionState.Running(replacement)
        advanceUntilIdle()
        rooms.emit(listOf(ProductChatRoom(roomId, ROOM_HOST)))
        advanceUntilIdle()

        verify(replacement, times(1)).notifyChatRoomsChanged(any())
        verify(first, times(1)).notifyChatRoomsChanged(any())
    }

    @Test
    fun `the lease is acquired once and released once when the scope is cancelled`() = runTest {
        val runtime: TrUAPIHostRuntime = mock()
        val workerScope = CoroutineScope(StandardTestDispatcher(testScheduler))

        worker(runtime = runtime, scope = workerScope)

        verify(runtime, times(1)).acquireWorker(productId.value)
        verify(runtime, never()).releaseWorker(productId.value)

        workerScope.cancel()
        advanceUntilIdle()

        verify(runtime, times(1)).releaseWorker(productId.value)
    }
}
