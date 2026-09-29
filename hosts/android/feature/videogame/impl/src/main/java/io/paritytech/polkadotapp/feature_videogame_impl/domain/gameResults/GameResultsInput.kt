package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import java.math.BigDecimal

/** Payload delivered to the game-results webview. */
data class GameResultsInput(
    val attestations: Attestations,
    val member: MemberState,
    val prizeDraw: PrizeDraw?,
    val usernameClaim: UsernameClaim,
    /**
     * Ordered matched attestation hashes (64-char hex, no prefix). Streamed one-by-one
     * via `pushAttestation`; intentionally NOT part of the `setGameResults` payload.
     */
    val attestationHashes: List<String>,
    val claim: AirdropClaimParams?
)

data class AirdropClaimParams(
    val gameIndex: Int,
    val recognized: Boolean
)

data class Attestations(
    /**
     * 0..[total]. Also the number of attestations native streams via
     * `pushAttestation` on a failed game; a passed game always streams 10.
     */
    val score: Int,
    val total: Int,
    /** Native-authoritative — not derived from score/total. */
    val passed: Boolean
)

data class MemberState(
    /** Candidate → first member tier; the canonical "got personhood" signal. */
    val justBecameMember: Boolean,
    /** Max 24 chars; host sanitises. */
    val displayName: String?,
    /** ISO date. */
    val memberSince: String?
)

data class PrizeDraw(
    /** Prize amount in W3T units (200 normal week, 2000 monthly bonus). */
    val prizeUsd: BigDecimal,
    /** User's ticket hash — 32 bytes as 64-char lowercase hex. */
    val userTicket: String,
    /** All winning ticket hashes this draw (~20), same hex shape as [userTicket]. */
    val winningTickets: List<String>,
    /** Distance from [userTicket] to nearest winner; 0 = won. */
    val ticketDistance: Long,
    /** Total tickets in this draw's pool. */
    val totalEntries: Long,
    /** ISO 8601 timestamp of the next weekly draw. */
    val nextDrawAt: String,
    /** Native-authoritative. */
    val won: Boolean
)

data class UsernameClaim(
    val eligible: Boolean,
    /** Clean base name, no suffix (e.g. "byteboro"). */
    val suggestedUsername: String?,
    /** Current candidate handle suffixed with `.NN` (e.g. "byteboro.42"). */
    val previousUsername: String?,
    /** Result of the People Chain base-name query. */
    val availability: UsernameAvailability?,
    /** ≤5 alternatives, only meaningful when [availability] is TAKEN. */
    val alternatives: List<String>?
)

enum class UsernameAvailability(val wireValue: String) {
    AVAILABLE("available"),
    TAKEN("taken"),
    UNKNOWN("unknown")
}

/**
 * One streamed passed-attestation, delivered via `window.pushAttestation(...)`.
 * Sits outside [GameResultsInput] because each arrives independently and may
 * straddle screen transitions.
 */
data class AttestationPush(
    /** 0-based slot in the user's attestation sequence. */
    val index: Int,
    /** 32-byte attestation hash as 64 hex chars (optional 0x prefix). */
    val hash: String,
    /** Advisory rarity hint; the web resolver derives authoritative rarity from the hash. */
    val highValue: Boolean?
)
