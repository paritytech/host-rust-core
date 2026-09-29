package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings

/**
 * How many hop discs a row can show, and how many it had to hand to the overflow chip.
 *
 * [hiddenHops] is zero when everything fits. When it is not, [showChip] is true and the chip carries the
 * count — hops are never silently dropped.
 */
internal class CoinMarkLayout(
    val discCount: Int,
    val showChip: Boolean,
    val hiddenHops: Int,
)

/**
 * Fits discs into the column, giving one disc's place to the chip when anything would be lost.
 *
 * A disc that would be clipped is never drawn part-way, so the count is exact rather than "as much as fits".
 * If the column cannot hold even the chip the row shows no marks at all and falls through to the unknown
 * pair alone, which still says something true — that nothing about this stretch of the coin's past is shown.
 */
internal fun coinMarkLayout(
    columnWidth: Float,
    discDiameter: Float,
    gap: Float,
    chipMinWidth: Float,
    hopCount: Int,
): CoinMarkLayout {
    if (hopCount <= 0 || columnWidth < discDiameter) {
        return CoinMarkLayout(discCount = 0, showChip = false, hiddenHops = hopCount.coerceAtLeast(0))
    }

    // Largest run of discs that fits: k discs need k diameters and the k-1 gaps between them.
    val fittingDiscs = ((columnWidth + gap) / (discDiameter + gap)).toInt().coerceAtMost(hopCount)

    if (fittingDiscs == hopCount) {
        return CoinMarkLayout(discCount = hopCount, showChip = false, hiddenHops = 0)
    }

    // Something has to be hidden, so one more disc gives up its place — and keeps giving it up until the
    // chip actually fits, since a chip is wider than the disc it replaces.
    var discs = fittingDiscs - 1
    while (discs > 0 && columnWidth - discs * (discDiameter + gap) < chipMinWidth) {
        discs--
    }

    if (columnWidth < chipMinWidth) {
        return CoinMarkLayout(discCount = 0, showChip = false, hiddenHops = hopCount)
    }

    return CoinMarkLayout(discCount = discs, showChip = true, hiddenHops = hopCount - discs)
}
