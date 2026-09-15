package io.paritytech.polkadotapp.feature_coinage_api.domain.model

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.feature_members_api.data.model.RingIndex

typealias RingVrfIndex = Int
typealias RecyclerIndex = RingIndex

data class RecyclerVoucher(
    val ringVrfKeyIndex: RingVrfIndex,
    val ringVrfPublicKey: BandersnatchPublicKey,
    val recyclerValue: ValueExponent,
    val location: Location,
) {
    sealed interface Location {
        data object Unknown : Location
        data object Onboarding : Location
        data class InRecycler(
            val recyclerIndex: RecyclerIndex,
            /**
             * Keys baked into the ring's root, which is the set a proof actually verifies against — so it is
             * the anonymity this voucher really has, not how many keys the ring has been offered.
             */
            val recyclerMembers: Int,
        ) : Location
    }
}

fun RecyclerVoucher.tokenAmount() = recyclerValue.tokenAmount()

fun RecyclerVoucher.isInRecycler() = location is RecyclerVoucher.Location.InRecycler

fun RecyclerVoucher.recyclerLocationOrThrow() = location as RecyclerVoucher.Location.InRecycler

/** A voucher outside a recycler hides in nothing, which is the same as an empty ring. */
fun RecyclerVoucher.recyclerMembersOrZero() =
    (location as? RecyclerVoucher.Location.InRecycler)?.recyclerMembers ?: 0

fun List<RecyclerVoucher>.filterInRecycler(): List<RecyclerVoucher> {
    return filter { it.isInRecycler() }
}
