package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models

import io.paritytech.polkadotapp.common.domain.model.AccountId

/**
 * Calculates the "sugar level" (0f–1f) representing how confident we are
 * that the player's gesture is legitimate, based on peer acceptances.
 *
 * Both the host's share and each non-host's incremental contribution are
 * scaled by `k` — the number of eligible non-host players in the round
 * (`k = totalPlayers - localPlayer - host`) — so that a full house always
 * tops out at exactly 100% and small games still get a satisfying ramp:
 *
 * ```
 * | k | Players | Host | Non-host steps (incremental) | Full house |
 * |---|---------|------|------------------------------|------------|
 * | 0 | 2       | 100% | —                            | 100%       |
 * | 1 | 3       |  70% | [30]                         | 100%       |
 * | 2 | 4       |  60% | [15, 25]                     | 100%       |
 * | 3 | 5       |  50% | [10, 15, 25]                 | 100%       |
 * | 4 | 6       |  40% | [5, 10, 15, 30]              | 100%       |
 * ```
 *
 * Non-host steps are awarded *in order of arrival*, not by identity — the
 * i-th non-host acceptance contributes the i-th value in the row regardless
 * of which `AccountId` it came from. The host is identified by
 * [hostAccountId] and contributes the matching `HOST_SUGAR_BY_K[k]` entry on
 * acceptance.
 *
 * Special cases:
 * - `hostAccountId == null` → 0 (round host unknown, can't compute).
 * - Local player is the host → handled at the call site; this function
 *   returns whatever the formula yields, which will be 0 if `acceptorIds`
 *   is empty (host doesn't receive acceptances).
 * - `k = 0` (solo round) → only the host can fill the bar, alone, to 100%.
 *
 * @param acceptorIds AccountIds of peers who accepted the gesture.
 * @param hostAccountId The current round's host AccountId, or null if
 *  unknown.
 * @param eligibleNonHostPlayerCount Players in the round who are neither
 *  the local player nor the host. Determines which row of the per-k tables
 *  is used; values above [NON_HOST_STEPS_BY_K]`.lastIndex` are clamped.
 * @return Sugar level as a float between 0f (no acceptances) and 1f
 *  (full confidence).
 */
fun calculateSugarLevel(
    acceptorIds: Set<AccountId>,
    hostAccountId: AccountId?,
    eligibleNonHostPlayerCount: Int,
): Float {
    if (hostAccountId == null) return 0f

    val hostAccepted = acceptorIds.contains(hostAccountId)
    val nonHostAcceptances = if (hostAccepted) acceptorIds.size - 1 else acceptorIds.size
    if (!hostAccepted && nonHostAcceptances == 0) return 0f

    val k = eligibleNonHostPlayerCount.coerceIn(0, NON_HOST_STEPS_BY_K.lastIndex)
    val nonHostSugar = NON_HOST_STEPS_BY_K[k].take(nonHostAcceptances).sum()
    val hostSugar = if (hostAccepted) HOST_SUGAR_BY_K[k] else 0f

    return (nonHostSugar + hostSugar).coerceIn(0f, 1f)
}

// Incremental sugar per non-host acceptance, indexed by the number of
// eligible non-host players in the round. Each row sums with the matching
// HOST_SUGAR_BY_K entry to exactly 1.0 so a full house always reaches 100%.
private val NON_HOST_STEPS_BY_K = listOf(
    emptyList(), // k=0 -> 2 players (host only)
    listOf(0.30f), // k=1 -> 3 players
    listOf(0.15f, 0.25f), // k=2 -> 4 players
    listOf(0.10f, 0.15f, 0.25f), // k=3 -> 5 players
    listOf(0.05f, 0.10f, 0.15f, 0.30f), // k=4 -> 6 players
)

private val HOST_SUGAR_BY_K = listOf(
    1.00f, // k=0 -> host fills the bar alone
    0.70f, // k=1
    0.60f, // k=2
    0.50f, // k=3
    0.40f, // k=4
)
