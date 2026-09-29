package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import uniffi.truapi.HostRemindNextGameException
import uniffi.truapi.ProductExecutionKind
import io.parity.truapi.TrUAPIHostRuntime
import io.paritytech.polkadotapp.common.data.storage.preferences.encrypted.EncryptedPreferences
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_products_api.domain.game.ProductGameReminder
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.HostApiInteractor
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.navigation.NavigationPolicy
import io.paritytech.polkadotapp.feature_products_impl.domain.pocket.PocketCardStore
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.stubbing.Answer

class ProductTrUAPIHostBridgeTest {
    // The core refuses the open: an unavailable loopback port, or an execution config it rejects.
    private val refusingCore = Answer<Any> { throw IllegalStateException("loopback port unavailable") }

    private val gameReminder = mock(ProductGameReminder::class.java)
    private val game = ProductId.fromStoredValue("game.dot")

    private fun TestScope.bridge() = ProductTrUAPIHostBridge(
        hostApiInteractor = mock(HostApiInteractor::class.java),
        chainHttpClient = OkHttpClient(),
        encryptedPreferences = mock(EncryptedPreferences::class.java),
        confirmationLauncher = mock(TrUAPIConfirmationLauncher::class.java),
        appLifecycleObserver = mock(AppLifecycleObserver::class.java),
        dotNsTldProvider = mock(DotNsTldProvider::class.java),
        pocketCardStore = mock(PocketCardStore::class.java),
        productGameReminder = gameReminder,
        scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
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

    @Test
    fun `an accepted reminder returns and a refused one throws Busy`() = runTest {
        val gameBridge = bridge().gameBridge(game)
        whenever(gameReminder.schedule(game, 1_000, false, true)).thenReturn(true)
        whenever(gameReminder.schedule(game, 1_000, true, false)).thenReturn(false)

        gameBridge.scheduleReminder(1_000u, false, true)
        verify(gameReminder).schedule(game, 1_000, false, true)

        val error = runCatching { gameBridge.scheduleReminder(1_000u, true, false) }.exceptionOrNull()

        assertTrue(error is HostRemindNextGameException.Busy)
    }
}
