package io.paritytech.polkadotapp.feature_coinage_api.domain.recycling

import io.paritytech.polkadotapp.common.utils.Fraction

/**
 * How aggressively coins are moved through the recycler.
 *
 * The named strategies are points in this space rather than separate policies, so a later release can open
 * up the space itself — intermediate positions, then both axes independently — without the gating logic
 * changing.
 */
data class RecyclingParams(
    /**
     * Share of the balance that may be unavailable at once while recycling.
     *
     * A ceiling, not a target: it exists so more than one coin can be in flight. Coins the chain's age limit
     * forces ignore it, which is why the minimum-privacy strategy can set it to zero and still recycle.
     */
    val maxUnavailableBalance: Fraction,
    /** Coins below this age are not considered for recycling at all. */
    val minRecyclingAge: MinRecyclingAge,
    /**
     * How full a recycler's ring must be before a voucher taken from it counts as spendable again.
     *
     * Below a full ring the random unload delay is accepted in its place; at a full ring nothing else will
     * do. This is the parameter that produces the spendability delay the user is choosing between.
     */
    val requiredRingFill: Fraction,
    /**
     * Whether balance held back for privacy may still be spent, once the user has confirmed they accept the
     * loss. False for the strategy whose whole point is that it will not.
     */
    val allowsConfirmedSpend: Boolean,
)

/**
 * The age a preset starts recycling at, stated so that building the params needs no chain read.
 *
 * A preset that tracks the chain's own limit cannot name an age up front — the runtime may move it — so it
 * describes the threshold here and the strategy resolves it when it is asked for a verdict.
 */
sealed interface MinRecyclingAge {
    /**
     * The age the chain stops accepting a coin at, divided by [divisor].
     *
     * A divisor of one is the limit itself. Anything softer is a share of it, so the preset stays correct
     * relative to the chain rather than drifting when the runtime changes the limit.
     */
    data class UseChainLimit(val divisor: Int) : MinRecyclingAge

    /** A fixed age, for a preset whose threshold is deliberately unrelated to the chain's limit. */
    data class Override(val age: Int) : MinRecyclingAge
}
