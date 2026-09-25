package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import android.net.Uri
import dagger.Lazy
import io.parity.truapi.TrUAPIHostRuntime
import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
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
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * The boot runs on real threads here: a virtual-time dispatcher cannot place a STOP inside the
 * window between the boot's last suspension and the state it publishes.
 */
class TrUAPIWorkerSupervisorStopRaceTest {
    private val productId = ProductId.fromStoredValue("chat.dot")

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

    private class FixedDispatchers(private val dispatcher: CoroutineDispatcher) : CoroutineDispatchers {
        override val main: CoroutineDispatcher = dispatcher
        override val io: CoroutineDispatcher = dispatcher
        override val computation: CoroutineDispatcher = dispatcher
    }

    // Mockito's static mocks are thread-local, so every pool thread opens its own for its whole life.
    private fun uriParsingPool(uri: Uri) = Executors.newFixedThreadPool(POOL_THREADS) { runnable ->
        Thread {
            val uris = mockStatic(Uri::class.java)
            uris.`when`<Uri> { Uri.parse(any()) }.thenReturn(uri)
            uris.use { runnable.run() }
        }
    }

    @Test
    fun `a STOP that lands before the boot publishes leaves no Running on the disposed execution`() {
        val uri: Uri = mock()
        whenever(uri.scheme).thenReturn("https")
        whenever(uri.host).thenReturn("chat.dot")
        whenever(uri.port).thenReturn(-1)
        whenever(uri.path).thenReturn("/worker.js")
        val pool = uriParsingPool(uri)
        try {
            val pageFinished = AtomicReference<() -> Unit>()
            val listenerRegistered = CountDownLatch(1)
            val bootAtLastStep = CountDownLatch(1)
            val stopApplied = CountDownLatch(1)
            val accessCalls = AtomicInteger()

            val provider: ChatWebViewProvider = mock()
            whenever(provider.addOnPageFinishedListener(any())).thenAnswer { invocation ->
                pageFinished.set(invocation.getArgument(0))
                listenerRegistered.countDown()
            }
            // The supervisor's stop() disposes the runtime after it has dropped the worker.
            whenever(provider.getWebViewOrNull()).thenAnswer {
                stopApplied.countDown()
                null
            }
            runBlocking {
                whenever(provider.accessWebView<Unit>(any())).thenAnswer {
                    if (accessCalls.incrementAndGet() == LAST_BOOT_STEP) {
                        bootAtLastStep.countDown()
                        stopApplied.await(WAIT_SECONDS, TimeUnit.SECONDS)
                    }
                    null
                }
            }

            val webViewProviderFactory: ChatWebViewProvider.Factory = mock()
            whenever(webViewProviderFactory.create(any(), any())).thenReturn(provider)
            val bootstrapInstaller: TrUAPIBootstrapInstaller = mock()
            whenever(bootstrapInstaller.installerFor(any(), any())).thenReturn({ })
            val execution: TrUAPIProductExecution = mock()
            val hostBridge: ProductTrUAPIHostBridge = mock()
            val hostBridgeFactory: ProductTrUAPIHostBridge.Factory = mock()
            whenever(hostBridgeFactory.create(any())).thenReturn(hostBridge)
            val runtimeProvider: TrUAPIHostRuntimeProvider = mock()
            val refCounter: ProductWorkerRefCounter = mock()
            whenever(refCounter.chatMessaging(productId)).thenReturn(FakeChatMessaging())
            runBlocking {
                whenever(runtimeProvider.runtime()).thenReturn(Result.success(mock<TrUAPIHostRuntime>()))
                whenever(hostBridge.attach(any(), any(), any(), any(), any(), any(), any()))
                    .thenReturn(Result.success(execution))
            }

            val supervisor = TrUAPIWorkerSupervisor(
                runtimeProvider = Lazy { runtimeProvider },
                hostBridgeFactory = hostBridgeFactory,
                chainDirectory = mock<TrUAPIChainDirectory>(),
                scriptResolver = FixedScriptResolver(),
                webViewProviderFactory = webViewProviderFactory,
                bootstrapInstaller = bootstrapInstaller,
                refCounter = Lazy { refCounter },
                dispatchers = FixedDispatchers(pool.asCoroutineDispatcher()),
            )

            supervisor.onDemandChanged(productId, WorkerDemand.START)
            assertTrue("the boot never registered its ready listener", listenerRegistered.await(WAIT_SECONDS, TimeUnit.SECONDS))
            pageFinished.get().invoke()
            assertTrue("the boot never reached its last step", bootAtLastStep.await(WAIT_SECONDS, TimeUnit.SECONDS))

            supervisor.onDemandChanged(productId, WorkerDemand.STOP)
            assertTrue("the STOP never disposed the worker", stopApplied.await(WAIT_SECONDS, TimeUnit.SECONDS))

            repeat(SETTLE_POLLS) {
                assertNull(
                    "a boot that finishes after its STOP must not publish a Running",
                    supervisor.currentExecution(productId),
                )
                Thread.sleep(SETTLE_POLL_MS)
            }
        } finally {
            pool.shutdownNow()
        }
    }

    private companion object {
        // initialize() takes the first WebView access, loadEntryModule() the last one before the publish.
        const val POOL_THREADS = 3
        const val LAST_BOOT_STEP = 2
        const val WAIT_SECONDS = 5L
        const val SETTLE_POLLS = 30
        const val SETTLE_POLL_MS = 10L
    }
}
