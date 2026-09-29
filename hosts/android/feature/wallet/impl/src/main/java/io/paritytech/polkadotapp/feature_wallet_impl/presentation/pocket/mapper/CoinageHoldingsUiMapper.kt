package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.mapper

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageBalance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Hop
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerFungibility
import io.paritytech.polkadotapp.feature_tokens_api.presentation.mapper.TokenAmountMapper
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.CoinageHolding
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinHopUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageCompositionUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageHoldingUiModel
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.toImmutableList

fun List<CoinageHolding>.toUiModels(
    asset: Chain.Asset,
    amountMapper: TokenAmountMapper,
): ImmutableList<CoinageHoldingUiModel> = map { holding ->
    val value = amountMapper.mapFrom(asset.withAmount(holding.value))

    when (holding) {
        is CoinageHolding.CoinHolding -> CoinageHoldingUiModel.CoinRow(
            value = value,
            isSpendable = holding.isSpendable,
            hops = holding.hops.map { it.toUiModel() }.toImmutableList(),
            blockBarEnd = holding.recyclerFungibility?.toBarEnd(),
        )

        is CoinageHolding.VoucherHolding -> CoinageHoldingUiModel.VoucherRow(
            value = value,
            canUnloadNow = holding.isSpendable,
            solidBarEnd = holding.frozenMax().toBarEnd(),
            barberPoleEnd = holding.barberPoleEnd(),
        )
    }
}.toImmutableList()

/**
 * What is not ready yet, for any reason. Gaining privacy and pending are one bucket on screen: to the user
 * both are simply not usable yet, and the distinction between them only matters to the recycler.
 */
val CoinageBalance.clearing: Balance
    get() = gainingPrivacy.amount + pending

fun CoinageBalance.toCompositionUiModel(): CoinageCompositionUiModel {
    val total = total.value.toDouble()
    if (total <= 0.0) return CoinageCompositionUiModel.EMPTY

    return CoinageCompositionUiModel(
        readyFraction = availablePrivate.fractionOf(total),
        clearingFraction = clearing.fractionOf(total),
    )
}

/**
 * The max fungibility is frozen against one unloaded count, and the runtime can *decrement* that count when
 * an alias is marked unloaded — so a later current fungibility can legitimately exceed the frozen max. The
 * view absorbs that rather than the calculator, because it is a real state and not a bad read: the barber
 * pole simply cannot start before the solid bar it follows.
 */
private fun CoinageHolding.VoucherHolding.barberPoleEnd(): Float =
    recyclerFungibility.toBarEnd().coerceAtLeast(frozenMax().toBarEnd())

/**
 * A voucher whose maximum has not been frozen yet draws the same maximal bar a frozen zero would.
 *
 * The two states are worth keeping apart in storage — one is still writable, the other never again — but on
 * screen they say the same thing: no anonymity established to draw against.
 */
private fun CoinageHolding.VoucherHolding.frozenMax(): RecyclerFungibility =
    maxRecyclerFungibility ?: RecyclerFungibility.NONE

/**
 * A bar's end as a fraction of the column, from a fungibility percentage.
 *
 * Length is traceability, so the scale runs the opposite way to the percentage: full fungibility draws
 * nothing, none of it draws the whole column.
 */
private fun RecyclerFungibility.toBarEnd(): Float = (1f - percent / PERCENT).toFloat()

private fun Hop.toUiModel(): CoinHopUiModel {
    // A crowd of one hid in nothing, so it gets no dots; beyond the cap the exact number stops being
    // legible at this size and the reader only needs "several".
    val crowd = when (this) {
        is Hop.Transfer -> bundleSize
        is Hop.Split -> fanout
    }

    return CoinHopUiModel(dotCount = (crowd - 1).coerceIn(0, MAX_HOP_DOTS))
}

private fun Balance.fractionOf(total: Double): Float = (value.toDouble() / total).toFloat()

private const val MAX_HOP_DOTS = 4
private const val PERCENT = 100.0
