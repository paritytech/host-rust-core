package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings

/** The two segments of a voucher row's bar, in pixels. They abut, so the bar is their sum. */
internal class VoucherBarLayout(
    val solidWidth: Float,
    val poleWidth: Float,
) {
    val totalWidth: Float
        get() = solidWidth + poleWidth
}

/**
 * Splits a voucher's bar into the traceability that will remain and the privacy still to be earned.
 *
 * The solid segment runs to `solidEnd` and the striped one on to `poleEnd`, both fractions of [columnWidth].
 * They meet without a gap: this is one bar whose length is how traceable the voucher is, divided at the
 * point its ring can no longer improve on.
 *
 * Neither segment has a floor of its own, so either may round away to nothing and leave the other holding
 * the whole bar. Only the bar as a whole is floored, at [minWidth], and both segments are then scaled into
 * that length. Scaling rather than padding is the point: a minimum applied to one segment would buy
 * legibility by reporting a ratio the voucher does not have.
 *
 * Both ends at zero is not an empty reading but the best one there is, since full fungibility draws nothing.
 * It has no gap left to earn, so the floor goes entirely to the solid segment.
 */
internal fun voucherBarLayout(
    columnWidth: Float,
    minWidth: Float,
    solidEnd: Float,
    poleEnd: Float,
): VoucherBarLayout {
    val totalWidth = (poleEnd * columnWidth)
        .coerceAtLeast(minWidth)
        .coerceAtMost(columnWidth)

    if (poleEnd <= 0f) return VoucherBarLayout(solidWidth = totalWidth, poleWidth = 0f)

    val solidWidth = totalWidth * (solidEnd / poleEnd).coerceIn(0f, 1f)

    return VoucherBarLayout(solidWidth = solidWidth, poleWidth = totalWidth - solidWidth)
}
