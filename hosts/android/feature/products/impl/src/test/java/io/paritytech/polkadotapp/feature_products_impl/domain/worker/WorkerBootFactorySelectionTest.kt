package io.paritytech.polkadotapp.feature_products_impl.domain.worker

import dagger.Lazy
import io.parity.truapi.TrUAPIHostRuntime
import io.paritytech.polkadotapp.feature_products_api.domain.runtime.ProductRuntimeSettings
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.FakeChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductsBotApi
import io.paritytech.polkadotapp.feature_products_impl.domain.scriptExecutor.HostApiProductsScriptExecutor
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIHostRuntimeProvider
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker.TrUAPIChatWorker
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker.TrUAPIWorkerSupervisor
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.verifyNoInteractions

class WorkerBootFactorySelectionTest {
    private val productId = ProductId.fromStoredValue("chat.dot")
    private val botApi: ProductsBotApi = mock()
    private val chatMessaging: ProductChatMessaging = FakeChatMessaging()

    private fun TestScope.factory(
        runtimeSettings: ProductRuntimeSettings,
        runtimeProvider: TrUAPIHostRuntimeProvider = mock(),
        workerSupervisor: TrUAPIWorkerSupervisor = mock(),
        scriptExecutorFactory: HostApiProductsScriptExecutor.Factory = mock(),
    ): RealWorkerBootFactory = RealWorkerBootFactory(
        scriptExecutorFactory = scriptExecutorFactory,
        runtimeSettings = runtimeSettings,
        runtimeProvider = Lazy { runtimeProvider },
        workerSupervisor = Lazy { workerSupervisor },
    )

    private fun settingsWith(enabled: Boolean): ProductRuntimeSettings {
        val settings: ProductRuntimeSettings = mock()
        whenever(settings.isTrUAPIRuntimeEnabled()).thenReturn(enabled)
        return settings
    }

    private suspend fun jsExecutorFactory(executor: HostApiProductsScriptExecutor, scope: CoroutineScope): HostApiProductsScriptExecutor.Factory {
        val scriptExecutorFactory: HostApiProductsScriptExecutor.Factory = mock()
        whenever(scriptExecutorFactory.create(productId)).thenReturn(executor)
        whenever(executor.initializeBot(botApi, scope)).thenReturn(Result.success(Unit))
        return scriptExecutorFactory
    }

    @Test
    fun `setting off boots the JS worker`() = runTest {
        val runtimeProvider: TrUAPIHostRuntimeProvider = mock()
        val executor: HostApiProductsScriptExecutor = mock()
        val scriptExecutorFactory = jsExecutorFactory(executor, this)
        val factory = factory(
            settingsWith(enabled = false),
            runtimeProvider = runtimeProvider,
            scriptExecutorFactory = scriptExecutorFactory,
        )

        val worker = factory.boot(productId, botApi, chatMessaging, this)

        assertSame("setting off must boot the JS worker unchanged", executor, worker)
        verifyNoInteractions(runtimeProvider)
    }

    @Test
    fun `setting on boots the core worker`() = runTest {
        val runtimeProvider: TrUAPIHostRuntimeProvider = mock()
        val runtime: TrUAPIHostRuntime = mock()
        whenever(runtimeProvider.runtime()).thenReturn(Result.success(runtime))
        val scriptExecutorFactory: HostApiProductsScriptExecutor.Factory = mock()
        val workerSupervisor: TrUAPIWorkerSupervisor = mock()
        whenever(workerSupervisor.executionState(productId)).thenReturn(emptyFlow())
        val factory = factory(
            settingsWith(enabled = true),
            runtimeProvider = runtimeProvider,
            workerSupervisor = workerSupervisor,
            scriptExecutorFactory = scriptExecutorFactory,
        )
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))

        val worker = factory.boot(productId, botApi, chatMessaging, scope)
        advanceUntilIdle()

        assertTrue("setting on must boot the core worker", worker is TrUAPIChatWorker)
        verifyNoInteractions(scriptExecutorFactory)
    }

    @Test
    fun `a construction failure on the core arm falls back to the JS worker`() = runTest {
        val runtimeProvider: TrUAPIHostRuntimeProvider = mock()
        val runtime: TrUAPIHostRuntime = mock()
        whenever(runtimeProvider.runtime()).thenReturn(Result.success(runtime))
        whenever(runtime.acquireWorker(productId.value)).thenThrow(IllegalStateException("acquireWorker boom"))
        val executor: HostApiProductsScriptExecutor = mock()
        val scriptExecutorFactory = jsExecutorFactory(executor, this)
        val factory = factory(
            settingsWith(enabled = true),
            runtimeProvider = runtimeProvider,
            scriptExecutorFactory = scriptExecutorFactory,
        )

        val worker = factory.boot(productId, botApi, chatMessaging, this)

        assertSame("a construction failure on the core arm must fall back to the JS worker", executor, worker)
    }
}
