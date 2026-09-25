package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import android.net.Uri
import dagger.Lazy
import io.parity.truapi.TrUAPIHostRuntime
import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.feature_products_api.model.ProductExecutable
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_api.model.SemVer
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.FakeChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.product.ProductScriptResolver
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.ProductTrUAPIHostBridge
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIBootstrapInstaller
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIChainDirectory
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIHostRuntimeProvider
import io.paritytech.polkadotapp.feature_products_impl.domain.webView.ChatWebViewProvider
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorkerRefCounter
import io.paritytech.polkadotapp.test_shared.any
import io.paritytech.polkadotapp.test_shared.testDispatchers
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import kotlin.coroutines.Continuation
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.resume

class TrUAPIWorkerSupervisorFailureTest {
    private val productId = ProductId.fromStoredValue("chat.dot")

    private class FailingScriptResolver(private val error: Throwable) : ProductScriptResolver {
        override suspend fun resolveWorker(productId: ProductId): Result<ProductExecutable.Worker> =
            Result.failure(error)
    }

    private class FixedScriptResolver : ProductScriptResolver {
        override suspend fun resolveWorker(productId: ProductId): Result<ProductExecutable.Worker> =
            Result.success(
                ProductExecutable.Worker(
                    scriptUrl = "https://chat.dot/worker.js",
                    appVersion = SemVer.ZERO,
                    includesChat = true,
                    includesPocket = false,
                    pocketCards = emptyList(),
                ),
            )
    }

    private class FailOnceThenGateScriptResolver(
        private val error: Throwable,
        private val gate: CompletableDeferred<Unit>,
    ) : ProductScriptResolver {
        private var calls = 0

        override suspend fun resolveWorker(productId: ProductId): Result<ProductExecutable.Worker> {
            calls++
            if (calls == 1) return Result.failure(error)
            gate.await()
            error("the gate never completes in this test")
        }
    }

    private fun TestScope.supervisorWith(
        scriptResolver: ProductScriptResolver,
        runtimeProvider: TrUAPIHostRuntimeProvider = mock(),
        hostBridgeFactory: ProductTrUAPIHostBridge.Factory = mock(),
        webViewProviderFactory: ChatWebViewProvider.Factory = mock(),
        bootstrapInstaller: TrUAPIBootstrapInstaller = mock(),
        refCounter: ProductWorkerRefCounter = mock(),
    ): TrUAPIWorkerSupervisor = TrUAPIWorkerSupervisor(
        runtimeProvider = Lazy { runtimeProvider },
        hostBridgeFactory = hostBridgeFactory,
        chainDirectory = mock<TrUAPIChainDirectory>(),
        scriptResolver = scriptResolver,
        webViewProviderFactory = webViewProviderFactory,
        bootstrapInstaller = bootstrapInstaller,
        refCounter = Lazy { refCounter },
        dispatchers = testDispatchers(),
    )

    @Test
    fun `a boot that fails is reported as failed, not as still pending`() = runTest {
        val boom = IllegalStateException("boom")
        val supervisor = supervisorWith(FailingScriptResolver(boom))

        supervisor.onDemandChanged(productId, WorkerDemand.START)
        advanceUntilIdle()

        val state = supervisor.executionState(productId).filterNotNull().first()
        assertTrue(state is WorkerExecutionState.Failed)
        assertSame(boom, (state as WorkerExecutionState.Failed).reason)
    }

    @Test
    fun `a STOP after the worker was already removed by the boot failure still clears the stale Failed`() = runTest {
        val boom = IllegalStateException("boom")
        val supervisor = supervisorWith(FailingScriptResolver(boom))

        supervisor.onDemandChanged(productId, WorkerDemand.START)
        advanceUntilIdle()
        assertTrue(supervisor.executionState(productId).first() is WorkerExecutionState.Failed)

        supervisor.onDemandChanged(productId, WorkerDemand.STOP)
        advanceUntilIdle()

        assertNull(
            "a STOP must clear the stale Failed even when the worker was already gone from the map",
            supervisor.executionState(productId).first(),
        )
    }

    @Test
    fun `a retry after a failed boot reports pending, not the stale failure`() = runTest {
        val boom = IllegalStateException("boom")
        val gate = CompletableDeferred<Unit>()
        val supervisor = supervisorWith(FailOnceThenGateScriptResolver(boom, gate))

        supervisor.onDemandChanged(productId, WorkerDemand.START)
        advanceUntilIdle()
        assertTrue(supervisor.executionState(productId).first() is WorkerExecutionState.Failed)

        supervisor.onDemandChanged(productId, WorkerDemand.START)
        advanceUntilIdle()

        assertNull(supervisor.executionState(productId).first())
    }

    @Test
    fun `a boot that finishes after its STOP publishes no Running`() = runTest {
        val provider: ChatWebViewProvider = mock()
        var pageFinished: () -> Unit = {}
        whenever(provider.addOnPageFinishedListener(any())).thenAnswer { pageFinished = it.getArgument(0); null }
        var accesses = 0
        var lastBootStep: Continuation<Any?>? = null
        whenever(provider.accessWebView<Unit>(any())).thenAnswer { invocation ->
            if (++accesses < 2) {
                null
            } else {
                @Suppress("UNCHECKED_CAST")
                lastBootStep = invocation.rawArguments.last() as Continuation<Any?>
                COROUTINE_SUSPENDED
            }
        }
        val webViewProviderFactory: ChatWebViewProvider.Factory = mock()
        whenever(webViewProviderFactory.create(any(), any())).thenReturn(provider)
        val bootstrapInstaller: TrUAPIBootstrapInstaller = mock()
        whenever(bootstrapInstaller.installerFor(any(), any())).thenReturn({ })
        val hostBridge: ProductTrUAPIHostBridge = mock()
        whenever(hostBridge.attach(any(), any(), any(), any(), any(), any(), any()))
            .thenReturn(Result.success(mock<TrUAPIProductExecution>()))
        val hostBridgeFactory: ProductTrUAPIHostBridge.Factory = mock()
        whenever(hostBridgeFactory.create(any())).thenReturn(hostBridge)
        val runtimeProvider: TrUAPIHostRuntimeProvider = mock()
        whenever(runtimeProvider.runtime()).thenReturn(Result.success(mock<TrUAPIHostRuntime>()))
        val refCounter: ProductWorkerRefCounter = mock()
        whenever(refCounter.chatMessaging(productId)).thenReturn(FakeChatMessaging())

        mockStatic(Uri::class.java).use { uris ->
            uris.`when`<Uri> { Uri.parse(any()) }.thenReturn(mock<Uri>())
            val supervisor = supervisorWith(
                FixedScriptResolver(),
                runtimeProvider = runtimeProvider,
                hostBridgeFactory = hostBridgeFactory,
                webViewProviderFactory = webViewProviderFactory,
                bootstrapInstaller = bootstrapInstaller,
                refCounter = refCounter,
            )

            supervisor.onDemandChanged(productId, WorkerDemand.START)
            runCurrent()
            pageFinished()
            runCurrent()
            val parked = requireNotNull(lastBootStep) { "the boot never reached its last step" }

            supervisor.onDemandChanged(productId, WorkerDemand.STOP)
            runCurrent()
            parked.resume(null)
            runCurrent()

            assertNull(
                "a boot that finishes after its STOP must not publish a Running",
                supervisor.currentExecution(productId),
            )
        }
    }
}
