package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

import io.paritytech.polkadotapp.feature_coinage_impl.domain.COINAGE_LOG_TAG
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DURABILITY_LOG_TAG
import org.junit.Assert.assertEquals
import org.junit.Test

class CoinageLogFilterTest {
    private val exportedTags = setOf(COINAGE_LOG_TAG, DURABILITY_LOG_TAG)

    @Test
    fun `keeps only entries carrying one of the given tags`() {
        val log = sequenceOf(
            entry("Network", "connected"),
            entry(COINAGE_LOG_TAG, "tx-submitted"),
            entry("Network", "disconnected")
        )

        val filtered = log.filterLogEntries(exportedTags, maxLines = 100)

        assertEquals(listOf(entry(COINAGE_LOG_TAG, "tx-submitted")), filtered)
    }

    @Test
    fun `keeps durability entries alongside coinage ones`() {
        val log = sequenceOf(
            entry(COINAGE_LOG_TAG, "tx-submitted"),
            entry(DURABILITY_LOG_TAG, "verdict=confirmed"),
            entry("Network", "disconnected")
        )

        val filtered = log.filterLogEntries(exportedTags, maxLines = 100)

        assertEquals(
            listOf(entry(COINAGE_LOG_TAG, "tx-submitted"), entry(DURABILITY_LOG_TAG, "verdict=confirmed")),
            filtered
        )
    }

    @Test
    fun `keeps stack trace lines that belong to a retained entry`() {
        val log = sequenceOf(
            entry(COINAGE_LOG_TAG, "tx-failed"),
            "java.lang.IllegalStateException: boom",
            "\tat io.paritytech.polkadotapp.Coinage.transfer(Coinage.kt:42)",
            entry("Network", "disconnected")
        )

        val filtered = log.filterLogEntries(exportedTags, maxLines = 100)

        assertEquals(3, filtered.size)
        assertEquals("\tat io.paritytech.polkadotapp.Coinage.transfer(Coinage.kt:42)", filtered.last())
    }

    @Test
    fun `drops stack trace lines that belong to another tag`() {
        val log = sequenceOf(
            entry("Network", "request-failed"),
            "java.net.SocketTimeoutException: timeout"
        )

        val filtered = log.filterLogEntries(exportedTags, maxLines = 100)

        assertEquals(emptyList<String>(), filtered)
    }

    @Test
    fun `drops the oldest lines and keeps the newest when the cap is reached`() {
        val log = (1..10).asSequence().map { entry(COINAGE_LOG_TAG, "entry-$it") }

        val filtered = log.filterLogEntries(exportedTags, maxLines = 3)

        assertEquals(
            listOf(
                entry(COINAGE_LOG_TAG, "entry-8"),
                entry(COINAGE_LOG_TAG, "entry-9"),
                entry(COINAGE_LOG_TAG, "entry-10")
            ),
            filtered
        )
    }

    private fun entry(tag: String, message: String) = "2026-09-07 10:00:00.000 $tag INFO $message"
}
