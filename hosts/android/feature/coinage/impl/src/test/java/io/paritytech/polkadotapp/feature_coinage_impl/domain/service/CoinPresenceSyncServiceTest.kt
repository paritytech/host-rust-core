package io.paritytech.polkadotapp.feature_coinage_impl.domain.service

import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinUpdate
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainCoinInfo
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinRepository
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeping each coin's on-chain presence current.
 *
 * Two things make this delicate. Its writes land in the `coins` table, which Room invalidates as a whole, so
 * a needless write re-runs every join in the app that reads a coin. And the age it writes is the only record
 * that a coin was ever on chain at all — clearing it would make a coin the peer took indistinguishable from
 * one nothing has looked at.
 */
class CoinPresenceSyncServiceTest {
    private val chainAssetProvider: ChainAssetProvider = mockk()
    private val coinRepository: CoinRepository = mockk()

    private val service = CoinPresenceSyncService(chainAssetProvider, coinRepository)

    private val written = mutableListOf<List<CoinUpdate>>()
    private val scope = CoroutineScope(UnconfinedTestDispatcher())

    @After
    fun stop() = scope.cancel()

    /**
     * A coin the chain no longer holds, already recorded as gone. Nothing about it has changed, so writing
     * it again only invalidates the table for every other reader.
     *
     * Its age is what makes it distinguishable from a coin never seen, so it is carried forward rather than
     * re-sent, which is precisely why the update looks like a change when it is not.
     */
    @Test
    fun `a coin that is still absent is not written again`() = runTest {
        givenCoins(coinOf(age = 5, onChain = false))
        givenChainHolds(emptyMap())

        startSync()

        assertTrue("expected no write, got $written", written.all { it.isEmpty() })
    }

    @Test
    fun `a coin that is still on chain at the same age is not written again`() = runTest {
        givenCoins(coinOf(age = 5, onChain = true))
        givenChainHolds(mapOf(ACCOUNT to OnChainCoinInfo(instanceId = 0, value = 3, age = 5)))

        startSync()

        assertTrue("expected no write, got $written", written.all { it.isEmpty() })
    }

    /** The coin has gone from the chain: presence drops, and no age is sent so the recorded one stands. */
    @Test
    fun `a coin that has left the chain is recorded as gone without losing its age`() = runTest {
        givenCoins(coinOf(age = 5, onChain = true))
        givenChainHolds(emptyMap())

        startSync()

        val update = written.flatten().single()
        assertEquals(false, update.onChain)
        assertEquals(null, update.age)
    }

    @Test
    fun `a coin that has appeared is recorded with the age the chain gave`() = runTest {
        givenCoins(coinOf(age = null, onChain = false))
        givenChainHolds(mapOf(ACCOUNT to OnChainCoinInfo(instanceId = 0, value = 3, age = 2)))

        startSync()

        val update = written.flatten().single()
        assertEquals(true, update.onChain)
        assertEquals(2, update.age)
    }

    @Test
    fun `a coin whose age has moved on is written with the new one`() = runTest {
        givenCoins(coinOf(age = 5, onChain = true))
        givenChainHolds(mapOf(ACCOUNT to OnChainCoinInfo(instanceId = 0, value = 3, age = 6)))

        startSync()

        assertEquals(6, written.flatten().single().age)
    }

    private suspend fun startSync() {
        with(ComputationalScope(scope)) { service.start() }
    }

    private fun givenCoins(vararg coins: Coin) {
        val asset: Chain.Asset = mockk()
        every { asset.chainId } returns "test-chain"
        coEvery { chainAssetProvider.asset() } returns asset

        every { coinRepository.subscribeAllCoins() } returns flowOf(coins.toList())
        coEvery { coinRepository.updateCoins(any()) } answers { written += firstArg<List<CoinUpdate>>() }
    }

    private fun givenChainHolds(coins: Map<AccountId, OnChainCoinInfo>) {
        coEvery { coinRepository.subscribeCoinsInfoFor(any(), any()) } answers {
            val requested = secondArg<List<AccountId>>()

            flowOf(Result.success(requested.associateWith { coins[it] }))
        }
    }

    private fun coinOf(age: Int?, onChain: Boolean) = Coin(
        derivationIndex = 0,
        valueExponent = ValueExponent(3),
        age = age?.let(Coin.Age::Known) ?: Coin.Age.Unknown,
        isOnChain = onChain,
        accountId = ACCOUNT,
    )

    private companion object {
        val ACCOUNT: AccountId = byteArrayOf(7).toDataByteArray()
    }
}
