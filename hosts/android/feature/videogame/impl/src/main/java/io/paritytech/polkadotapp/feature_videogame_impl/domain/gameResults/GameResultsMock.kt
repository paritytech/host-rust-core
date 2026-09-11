package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.random.Random

/**
 * Debug-only payload for the "Simulate game-results WebView" debug-menu entry —
 * not used in production. [happyPath] is the canonical pass + new-member + won +
 * username-available scenario.
 */
object GameResultsMock {
    fun happyPath(): GameResultsInput = GameResultsInput(
        attestations = Attestations(score = 8, total = 10, passed = true),
        member = MemberState(
            justBecameMember = true,
            displayName = "BYTEBORO",
            memberSince = null
        ),
        prizeDraw = PrizeDraw(
            prizeUsd = 200.toBigDecimal(),
            userTicket = ticketHash(seed = 1),
            winningTickets = winningTickets(includeUser = true),
            ticketDistance = 0L,
            totalEntries = 12_000L,
            nextDrawAt = Instant.now().plus(7, ChronoUnit.DAYS).toString(),
            won = true
        ),
        usernameClaim = UsernameClaim(
            eligible = true,
            suggestedUsername = "byteboro",
            previousUsername = "byteboro.42",
            availability = UsernameAvailability.AVAILABLE,
            alternatives = null
        ),
        attestationHashes = mockHashes(passed = true, score = 8),
        claim = null
    )

    /**
     * Mock attestation hashes: a passed game fills the full pack, a failed game streams `score`,
     * a skunk (score 0) streams none.
     */
    private fun mockHashes(passed: Boolean, score: Int): List<String> {
        val count = when {
            score == 0 -> 0
            passed -> SHELF_SIZE
            else -> score
        }
        return (0 until count).map { index -> ticketHash(seed = index + ATTESTATION_SEED_OFFSET) }
    }

    /** Deterministic 32-byte hash as 64 lowercase hex chars. */
    private fun ticketHash(seed: Int): String {
        val bytes = ByteArray(HASH_BYTES)
        Random(seed).nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun winningTickets(includeUser: Boolean): List<String> {
        val winners = (0 until WINNER_COUNT).map { ticketHash(seed = it + WINNER_SEED_OFFSET) }
        return if (includeUser) listOf(ticketHash(seed = 1)) + winners else winners
    }

    private const val SHELF_SIZE = 10
    private const val WINNER_COUNT = 20
    private const val HASH_BYTES = 32

    // Distinct seed namespaces so the user ticket, winners, and attestation
    // hashes never collide.
    private const val WINNER_SEED_OFFSET = 1_000
    private const val ATTESTATION_SEED_OFFSET = 10_000
}
