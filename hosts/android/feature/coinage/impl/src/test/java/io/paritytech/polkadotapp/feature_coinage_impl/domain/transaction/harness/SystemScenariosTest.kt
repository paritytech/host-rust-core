package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.harness

import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus.FINALIZED_SUCCESS
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus.PENDING
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.harness.TestActionFinality.FINALIZED
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.harness.TestActionFinality.IN_BEST
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** `coinage-durability-spec.md § Testing`, *System* — all four. */
class SystemScenariosTest {
    /**
     * A pass is triggered on every new head, and most heads arrive with nothing live in the ledger.
     * Such a pass decides nothing and propagates nothing, so it must not read the chain at all.
     *
     * Propagation walks the same set the decision loop does, which is what makes ending early safe: an empty
     * decidable set cannot hide work for it to do.
     */
    @Test
    fun `a pass with nothing to decide does not read the chain`() = scenario {
        mintCoinsOnChain(COIN_A, finality = FINALIZED)
        val id = givenEntryDecided(inputCoin = COIN_A, outputCoin = COIN_B, finality = FINALIZED)
        assertEquals(FINALIZED_SUCCESS, statusOf(id))

        val pinsBefore = chain.pins
        runPass()

        assertEquals("a settled ledger must not cost a chain read", pinsBefore, chain.pins)
    }

    @Test
    fun `a crash mid-pass does not prevent the next pass from starting`() = scenario {
        disableFallbackTxSearch()
        mintCoinsOnChain(COIN_A, finality = FINALIZED)
        val id = givenUnwatchedEntry(inputCoin = COIN_A, outputCoin = COIN_B)

        // The pass guards itself with an in-memory mutex; a crash has to take that with it, or the next
        // launch would find a lock nobody holds and skip every pass forever.
        makeChainUnreachable()
        assertTrue(recoveryPass.run().isFailure)
        crash()
        makeChainReachable()

        mintCoinsOnChain(COIN_B, finality = IN_BEST)
        finalizeToBest()
        runPass()

        assertEquals(FINALIZED_SUCCESS, statusOf(id))
    }

    @Test
    fun `a pass that aborts leaves its unreached work for the next one`() = scenario {
        disableFallbackTxSearch()
        mintCoinsOnChain(COIN_A, COIN_D, finality = FINALIZED)
        val first = givenUnwatchedEntry(inputCoin = COIN_A, outputCoin = COIN_B)
        val second = givenUnwatchedEntry(inputCoin = COIN_D, outputCoin = COIN_C)

        mintCoinsOnChain(COIN_B, finality = IN_BEST)
        mintCoinsOnChain(COIN_C, finality = IN_BEST)
        finalizeToBest()

        makeChainUnreachable()
        assertTrue(recoveryPass.run().isFailure)
        assertEquals(PENDING, statusOf(first))
        assertEquals(PENDING, statusOf(second))

        makeChainReachable()
        runPass()

        assertEquals(FINALIZED_SUCCESS, statusOf(first))
        assertEquals(FINALIZED_SUCCESS, statusOf(second))
    }

    @Test
    fun `best-chain height alone yields no terminal verdict while finality stalls`() = scenario {
        disableFallbackTxSearch()
        mintCoinsOnChain(COIN_A, finality = FINALIZED)
        val id = givenUnwatchedEntry(inputCoin = COIN_A, outputCoin = COIN_B)

        // Far past mortality on the best chain, but the finalized head never moves with it.
        chainReachesMortalityOf(id, finality = IN_BEST)

        runPass()

        assertEquals(PENDING, statusOf(id))
    }
}

private const val COIN_A = 1
private const val COIN_B = 2
private const val COIN_C = 3
private const val COIN_D = 4
