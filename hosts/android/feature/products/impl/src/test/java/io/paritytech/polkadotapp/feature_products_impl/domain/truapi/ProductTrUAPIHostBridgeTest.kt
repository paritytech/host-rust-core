package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import uniffi.truapi.ProductExecutionKind
import uniffi.truapi.WsBridgeEndpoint
import io.parity.truapi.TrUAPIHostRuntime
import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.common.data.storage.preferences.encrypted.EncryptedPreferences
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.HostApiInteractor
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.navigation.NavigationPolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.stubbing.Answer

class ProductTrUAPIHostBridgeTest {
    // The core refuses the open: an unavailable loopback port, or an execution config it rejects.
    private val refusingCore = Answer<Any> { throw IllegalStateException("loopback port unavailable") }

    private fun TestScope.bridge(
        scope: CoroutineScope = CoroutineScope(StandardTestDispatcher(testScheduler)),
        hostApiInteractor: HostApiInteractor = mock(HostApiInteractor::class.java),
    ) = ProductTrUAPIHostBridge(
        hostApiInteractor = hostApiInteractor,
        chainHttpClient = OkHttpClient(),
        encryptedPreferences = mock(EncryptedPreferences::class.java),
        confirmationLauncher = mock(TrUAPIConfirmationLauncher::class.java),
        appLifecycleObserver = mockk { every { subscribe() } returns emptyFlow() },
        dotNsTldProvider = mock(DotNsTldProvider::class.java),
        pocketCardStore = mockk { every { observeCards() } returns emptyFlow() },
        scope = scope,
    )

    // The callers launch attach into scopes with no handler, so a refusal from the core has to come
    // back as the Result the signature promises rather than as a crash.
    @Test
    fun `a core that refuses to open the execution fails the attach instead of throwing`() = runTest {
        val outcome = bridge().attach(
            runtime = mock(TrUAPIHostRuntime::class.java, refusingCore),
            productId = ProductId.fromStoredValue("game.dot"),
            chains = EMPTY_CHAINS,
            navigationPolicy = NavigationPolicy.DeeplinkNavigation(onDeeplinkNavigation = {}),
            kind = ProductExecutionKind.APP,
            onReadyToInject = {},
        )

        assertTrue(outcome.isFailure)
    }

    // The worker supervisor never holds the bridge; it stops a worker by cancelling the scope it
    // handed in. That cancel is what has to close the execution, or every card scrolled off screen
    // leaves its execution, loopback registration and chain sockets alive for the whole process.
    @Test
    fun `cancelling the owning scope closes the execution`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val execution = mockk<TrUAPIProductExecution>(relaxUnitFun = true) {
            every { startWsBridge(any()) } returns WsBridgeEndpoint(port = 1u, token = "token")
        }
        val runtime = mockk<TrUAPIHostRuntime> {
            every { openProductExecution(any(), any(), any(), any()) } returns execution
        }
        val bridge = bridge(scope, hostApiInteractor = mockk { every { subscribeTheme() } returns emptyFlow() })

        bridge.attach(
            runtime = runtime,
            productId = ProductId.fromStoredValue("game.dot"),
            chains = EMPTY_CHAINS,
            navigationPolicy = NavigationPolicy.DeeplinkNavigation(onDeeplinkNavigation = {}),
            kind = ProductExecutionKind.WORKER,
            onReadyToInject = {},
        )
        scope.cancel()
        advanceUntilIdle()

        verify { execution.stopWsBridge() }
        verify { execution.close() }
    }
}
