package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import junit.framework.TestCase.assertEquals
import org.junit.Test

class AcceptanceTierTest {
    private val host: AccountId = byteArrayOf(0x01).toDataByteArray()
    private val playerA: AccountId = byteArrayOf(0x0A).toDataByteArray()
    private val playerB: AccountId = byteArrayOf(0x0B).toDataByteArray()
    private val playerC: AccountId = byteArrayOf(0x0C).toDataByteArray()
    private val playerD: AccountId = byteArrayOf(0x0D).toDataByteArray()

    private companion object {
        const val EPSILON = 1e-6f
    }

    @Test
    fun `empty acceptors is zero`() {
        val sugar = calculateSugarLevel(
            acceptorIds = emptySet(),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 3,
        )

        assertEquals(0f, sugar, EPSILON)
    }

    @Test
    fun `null host is zero`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(playerA, playerB),
            hostAccountId = null,
            eligibleNonHostPlayerCount = 3,
        )

        assertEquals(0f, sugar, EPSILON)
    }

    @Test
    fun `solo round host accepted fills bar`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 0,
        )

        assertEquals(1f, sugar, EPSILON)
    }

    @Test
    fun `k1 host only accepted is 70 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 1,
        )

        assertEquals(0.70f, sugar, EPSILON)
    }

    @Test
    fun `k1 non-host only accepted is 30 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(playerA),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 1,
        )

        assertEquals(0.30f, sugar, EPSILON)
    }

    @Test
    fun `k1 full house is 100 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host, playerA),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 1,
        )

        assertEquals(1f, sugar, EPSILON)
    }

    @Test
    fun `k2 first non-host adds 15 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(playerA),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 2,
        )

        assertEquals(0.15f, sugar, EPSILON)
    }

    @Test
    fun `k2 host plus one non-host is 75 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host, playerA),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 2,
        )

        // host 60% + first non-host step 15% = 75%
        assertEquals(0.75f, sugar, EPSILON)
    }

    @Test
    fun `k2 full house is 100 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host, playerA, playerB),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 2,
        )

        assertEquals(1f, sugar, EPSILON)
    }

    @Test
    fun `k3 host plus two non-host is 75 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host, playerA, playerB),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 3,
        )

        // host 50% + first two non-host steps 10% + 15% = 75%
        assertEquals(0.75f, sugar, EPSILON)
    }

    @Test
    fun `k3 full house is 100 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host, playerA, playerB, playerC),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 3,
        )

        assertEquals(1f, sugar, EPSILON)
    }

    @Test
    fun `k4 only first non-host is 5 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(playerA),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 4,
        )

        assertEquals(0.05f, sugar, EPSILON)
    }

    @Test
    fun `k4 host plus three non-host is 70 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host, playerA, playerB, playerC),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 4,
        )

        // host 40% + first three non-host steps 5% + 10% + 15% = 70%
        assertEquals(0.70f, sugar, EPSILON)
    }

    @Test
    fun `k4 full house is 100 percent`() {
        val sugar = calculateSugarLevel(
            acceptorIds = setOf(host, playerA, playerB, playerC, playerD),
            hostAccountId = host,
            eligibleNonHostPlayerCount = 4,
        )

        assertEquals(1f, sugar, EPSILON)
    }
}
