package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery

import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainViewFactory
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The loop's whole job is deciding when to stop: too early strands a lock nothing else will release, too
 * late holds a foreground service up for nothing.
 */
class CoinageRecoveryLoopTest {
    private val repository: CoinageEntryRepository = mockk()
    private val recoveryPass: CoinageRecoveryPass = mockk()
    private val chainViewFactory: CoinageChainViewFactory = mockk()

    private val loop = CoinageRecoveryLoop(repository, recoveryPass, chainViewFactory)

    private var passesRun = 0

    @Test
    fun `a settled ledger costs one pass`() = runBlocking<Unit> {
        givenPassesSucceed()
        givenLiveWhilePassesBelow(1)
        givenHeads(1, 2, 3)

        loop.runUntilSettled()

        coVerify(exactly = 1) { recoveryPass.run() }
    }

    @Test
    fun `one pass per head until nothing is live`() = runBlocking<Unit> {
        givenPassesSucceed()
        // The launch pass plus two heads: the second head's pass is the one that settles the ledger.
        givenLiveWhilePassesBelow(3)
        givenHeads(1, 2, 3, 4)

        loop.runUntilSettled()

        coVerify(exactly = 3) { recoveryPass.run() }
    }

    @Test
    fun `a best head drives a pass just as a finalized one does`() = runBlocking<Unit> {
        givenPassesSucceed()
        givenLiveWhilePassesBelow(2)
        every { chainViewFactory.finalizedHeads() } returns emptyFlow()
        every { chainViewFactory.bestHeads() } returns blocks(1, 2, 3)

        loop.runUntilSettled()

        coVerify(exactly = 2) { recoveryPass.run() }
    }

    @Test
    fun `a lost head subscription fails the loop so its host can retry`() = runBlocking<Unit> {
        givenPassesSucceed()
        givenLiveWhilePassesBelow(Int.MAX_VALUE)
        every { chainViewFactory.finalizedHeads() } returns flow { throw IllegalStateException("socket closed") }
        every { chainViewFactory.bestHeads() } returns emptyFlow()

        val result = loop.runUntilSettled()

        assertTrue(result.isFailure)
    }

    @Test
    fun `an unreadable ledger keeps the loop running rather than abandoning entries`() = runBlocking<Unit> {
        givenPassesSucceed()
        coEvery { repository.hasLiveEntries() } returns Result.failure(IllegalStateException("no database"))
        givenHeads(1, 2)

        // It never settles by design, so the loop has to be cut off rather than awaited: the point is that
        // it ran every trigger and did not give up on the first unreadable answer.
        val settled = withTimeoutOrNull(TIMEOUT_MILLIS) { loop.runUntilSettled() }

        assertNull(settled)
        coVerify(exactly = 3) { recoveryPass.run() }
    }

    private fun givenPassesSucceed() {
        coEvery { recoveryPass.run() } answers { passesRun++; Result.success(Unit) }
    }

    private fun givenLiveWhilePassesBelow(threshold: Int) {
        coEvery { repository.hasLiveEntries() } answers { Result.success(passesRun < threshold) }
    }

    private fun givenHeads(vararg numbers: Int) {
        every { chainViewFactory.finalizedHeads() } returns blocks(*numbers)
        every { chainViewFactory.bestHeads() } returns emptyFlow()
    }

    private fun blocks(vararg numbers: Int) =
        flowOf(*numbers.map { BlockNumber(it.toBigInteger()) }.toTypedArray())

    private companion object {
        const val TIMEOUT_MILLIS = 500L
    }
}
