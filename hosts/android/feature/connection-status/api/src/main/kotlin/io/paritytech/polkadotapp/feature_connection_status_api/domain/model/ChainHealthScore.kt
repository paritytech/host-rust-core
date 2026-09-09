package io.paritytech.polkadotapp.feature_connection_status_api.domain.model

/**
 * A single chain-health score, always in the inclusive range 0..100 where 100 means perfect health.
 * Construct via [coerced] so the invariant holds regardless of raw scorer output.
 */
@JvmInline
value class ChainHealthScore private constructor(val value: Int) : Comparable<ChainHealthScore> {
    val fraction: Float
        get() = value / MAX_VALUE.toFloat()

    override fun compareTo(other: ChainHealthScore): Int = value.compareTo(other.value)

    companion object {
        const val MIN_VALUE = 0
        const val MAX_VALUE = 100

        val Perfect = ChainHealthScore(MAX_VALUE)
        val Zero = ChainHealthScore(MIN_VALUE)

        fun coerced(raw: Int): ChainHealthScore = ChainHealthScore(raw.coerceIn(MIN_VALUE, MAX_VALUE))
    }
}
