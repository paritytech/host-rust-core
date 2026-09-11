package io.paritytech.polkadotapp.feature_vouchers_impl.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext

val BandersnatchContext.Companion.PRIVACY_VOUCHER: BandersnatchContext
    get() = BandersnatchContext.fromString("pop:polkadot.network/priv-vouchr")
