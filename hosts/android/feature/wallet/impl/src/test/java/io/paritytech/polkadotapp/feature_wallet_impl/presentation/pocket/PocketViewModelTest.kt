package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket

import android.webkit.WebView
import androidx.lifecycle.viewModelScope
import io.paritytech.polkadotapp.common.presentation.sharing.SharingManager
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.BackupProgress
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsLoadProgress
import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCard
import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCardId
import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCardKey
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_api.presentation.spaHost.SpaHost
import io.paritytech.polkadotapp.feature_products_api.presentation.spaHost.SpaHostSession
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.mapper.TokenAmountMapper
import io.paritytech.polkadotapp.feature_videogame_api.domain.collectibles.CollectiblesUrlResolver
import io.paritytech.polkadotapp.feature_wallet_impl.PocketRouter
import io.paritytech.polkadotapp.feature_wallet_impl.domain.interactor.PocketInteractor
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.PocketRank
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketCardUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketScreenState
import io.paritytech.polkadotapp.test_shared.TestCoroutineDispatchers
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.stubbing.Answer

class PocketViewModelTest {
    // Every flow the screen combines answers empty unless a test says otherwise, so each test names
    // only the source it is about. observeRank is answered here rather than stubbed because its
    // context parameter cannot be named from a call site that does not have one.
    private val quietFlows = Answer { invocation ->
        when {
            invocation.method.name == "observeRank" -> flowOf(PocketRank.Basic)
            invocation.method.name == "warmUpProduct" -> Result.success(Unit)
            invocation.method.returnType == Flow::class.java -> emptyFlow<Any>()
            else -> null
        }
    }

    private val interactor: PocketInteractor = mock(PocketInteractor::class.java, quietFlows)

    // SpaHost.createSession carries context parameters, which cannot be named from a call site that
    // has none, so the mock answers it by name.
    private val hostedSession = FakeSpaHostSession()
    private val spaHost: SpaHost = mock(SpaHost::class.java, Answer { hostedSession })

    // One dispatcher for the screen's own scope and for the pool its card list is assembled on, so
    // the whole pipeline runs on this test's clock. Given a real background dispatcher the list
    // would be assembled on threads the test cannot advance, leaving it to wait on wall-clock time
    // and to lose that wait on a loaded machine.
    private val testDispatcher = StandardTestDispatcher()
    private val dispatchers = TestCoroutineDispatchers(testDispatcher)

    private class FakeSpaHostSession : SpaHostSession {
        override val webView = MutableStateFlow<WebView?>(null)
        override val currentUrl = MutableStateFlow("")
        override val loadProgress = MutableStateFlow<DotNsLoadProgress>(DotNsLoadProgress.Idle)
        override val title = MutableStateFlow("")
        override fun pauseConnections() = Unit
        override fun resumeConnections() = Unit
    }

    // The card list is shared eagerly in the view model's own scope, which outlives the test unless
    // it is cancelled.
    private val created = mutableListOf<PocketViewModel>()

    private fun createViewModel() = PocketViewModel(
        interactor = interactor,
        tokenAmountMapper = mock(TokenAmountMapper::class.java),
        tokenAmountFormatter = mock(TokenAmountFormatter::class.java),
        router = mock(PocketRouter::class.java),
        collectiblesUrlResolver = mock(CollectiblesUrlResolver::class.java),
        idShareImageRenderer = mock(IdShareImageRenderer::class.java),
        sharingManager = mock(SharingManager::class.java),
        dispatchers = dispatchers,
        spaHost = spaHost,
    ).also { created += it }

    /** The cards the screen holds once everything the view model started has run. */
    private fun TestScope.settledCards(viewModel: PocketViewModel): List<PocketCardUiModel> {
        advanceUntilIdle()

        return viewModel.cards.value
    }

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        whenever(interactor.observeUsername()).thenReturn(flowOf("alicent"))
        whenever(interactor.observeAddress()).thenReturn(flowOf("15oF4u"))
        whenever(interactor.observeBackupProgress()).thenReturn(flowOf(BackupProgress.Unknown))
        whenever(interactor.observeAccountBackupPending()).thenReturn(flowOf(false))
    }

    @After
    fun tearDown() {
        created.forEach { it.viewModelScope.cancel() }
        Dispatchers.resetMain()
    }

    private fun productCard(cardId: String) = PocketCard(
        key = PocketCardKey(ProductId.fromStoredValue("game.dot"), PocketCardId(cardId)),
        title = cardId,
        privileged = false,
    )

    // The collection is stored, decoded and served by a product's worker, so it has failure modes
    // the balance and identity cards do not share. Before the product cards joined this screen
    // nothing product-side could empty it; that must stay true.
    @Test
    fun `a failing product collection costs the product cards alone, not the native ones`() = runTest(testDispatcher) {
        whenever(interactor.observeProductCards()).thenReturn(flow { throw IllegalStateException("unreadable") })

        val cards = settledCards(createViewModel())

        assertEquals(listOf("digital_dollar_card", "id_card"), cards.map { it.id })
    }

    @Test
    fun `product cards follow the native ones once the collection loads`() = runTest(testDispatcher) {
        whenever(interactor.observeProductCards()).thenReturn(flowOf(listOf(productCard("loyalty"))))

        val cards = settledCards(createViewModel())

        assertEquals(
            listOf("digital_dollar_card", "id_card", "product_card:game.dot:loyalty"),
            cards.map { it.id },
        )
        assertEquals("loyalty", cards.filterIsInstance<PocketCardUiModel.ProductCard>().single().title)
    }

    // A product can remove its own card, and the collection can become unreadable, while the card
    // is open. The screen falls back to the list on its own, but the card stays selected unless
    // something clears it, so the card coming back pops the details view open with no tap — and the
    // product hosted under it was never taken down. Releasing that product is
    // ExpandedProductPageTest's half of this.
    @Test
    fun `a card that leaves the collection is no longer the selected one`() = runTest(testDispatcher) {
        val collection = MutableStateFlow(listOf(productCard("loyalty")))
        whenever(interactor.observeProductCards()).thenReturn(collection)

        val viewModel = createViewModel()
        val card = settledCards(viewModel).filterIsInstance<PocketCardUiModel.ProductCard>().single()
        viewModel.selectCard(card)
        advanceUntilIdle()
        assertTrue(viewModel.state.value is PocketScreenState.CardDetails)

        collection.value = emptyList()
        advanceUntilIdle()
        assertTrue(viewModel.state.value is PocketScreenState.List)

        collection.value = listOf(productCard("loyalty"))
        advanceUntilIdle()

        assertTrue("the card came back selected", viewModel.state.value is PocketScreenState.List)
        assertNull(viewModel.expandedProductSession.value)
    }
}
