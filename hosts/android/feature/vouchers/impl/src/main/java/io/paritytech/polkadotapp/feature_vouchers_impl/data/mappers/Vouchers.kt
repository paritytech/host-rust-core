package io.paritytech.polkadotapp.feature_vouchers_impl.data.mappers

import io.paritytech.polkadotapp.database.model.VoucherStateLocal
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherState

fun VoucherStateLocal.toDomain() = when (this) {
    VoucherStateLocal.GENERATED -> VoucherState.GENERATED
    VoucherStateLocal.REGISTERED -> VoucherState.REGISTERED
    VoucherStateLocal.CLAIMABLE -> VoucherState.CLAIMABLE
    VoucherStateLocal.CLAIMED -> VoucherState.CLAIMED
}

fun VoucherState.toLocal() = when (this) {
    VoucherState.GENERATED -> VoucherStateLocal.GENERATED
    VoucherState.REGISTERED -> VoucherStateLocal.REGISTERED
    VoucherState.CLAIMABLE -> VoucherStateLocal.CLAIMABLE
    VoucherState.CLAIMED -> VoucherStateLocal.CLAIMED
}
