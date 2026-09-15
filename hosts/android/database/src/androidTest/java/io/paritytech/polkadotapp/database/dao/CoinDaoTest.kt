package io.paritytech.polkadotapp.database.dao

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.database.AppDatabase
import io.paritytech.polkadotapp.database.model.CoinLocal
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A coin's presence and its age are two separate records, and only presence may go backwards.
 *
 * The age is the only evidence a coin was ever on chain. Clearing it when the coin leaves would make a coin
 * a peer has taken indistinguishable from one nothing has ever looked at, and those call for opposite
 * conclusions — the first ends a payment, the second says it is too early to say anything. The guarantee
 * lives in one SQL COALESCE, which is why it is pinned here rather than assumed.
 */
@RunWith(AndroidJUnit4::class)
class CoinDaoTest {

    private val accountId = byteArrayOf(0x07)

    private lateinit var database: AppDatabase

    @Before
    fun setUp() {
        database = Room.inMemoryDatabaseBuilder(
            InstrumentationRegistry.getInstrumentation().targetContext,
            AppDatabase::class.java
        ).build()
    }

    @After
    fun tearDown() = database.close()

    @Test
    fun aCoinThatLeavesTheChainKeepsTheAgeItWasLastSeenWith() = runBlocking {
        givenCoin(ageValue = 5, onChain = true)

        dao().updateCoinPresence(accountId = accountId, onChain = false, age = null)

        val coin = storedCoin()
        assertEquals("the last age seen must survive the coin leaving", 5, coin.ageValue)
        assertEquals(false, coin.onChain)
    }

    /** A coin nothing has ever seen has no age to keep, and must not gain one from being marked absent. */
    @Test
    fun aCoinNeverSeenOnChainStaysWithoutAnAge() = runBlocking {
        givenCoin(ageValue = null, onChain = false)

        dao().updateCoinPresence(accountId = accountId, onChain = false, age = null)

        assertNull(storedCoin().ageValue)
    }

    @Test
    fun anAgeTheChainGivesReplacesTheOneRecorded() = runBlocking {
        givenCoin(ageValue = 5, onChain = true)

        dao().updateCoinPresence(accountId = accountId, onChain = true, age = 6)

        assertEquals(6, storedCoin().ageValue)
    }

    /** Presence is the half that may go either way, and it decides what counts as on chain. */
    @Test
    fun onlyCoinsPresentRightNowCountAsOnChain() = runBlocking {
        givenCoin(ageValue = 5, onChain = true)
        dao().updateCoinPresence(accountId = accountId, onChain = false, age = null)

        assertEquals(emptyList<CoinLocal>(), dao().getOnChainCoins())

        dao().updateCoinPresence(accountId = accountId, onChain = true, age = null)

        assertEquals(1, dao().getOnChainCoins().size)
    }

    private fun dao() = database.coinDao()

    private suspend fun givenCoin(ageValue: Int?, onChain: Boolean) {
        dao().insert(
            CoinLocal(
                derivationIndex = 0,
                accountId = accountId,
                valueExponent = 3,
                ageValue = ageValue,
                onChain = onChain,
            )
        )
    }

    private suspend fun storedCoin(): CoinLocal =
        dao().getAll().single { it.accountId.toDataByteArray() == accountId.toDataByteArray() }
}
