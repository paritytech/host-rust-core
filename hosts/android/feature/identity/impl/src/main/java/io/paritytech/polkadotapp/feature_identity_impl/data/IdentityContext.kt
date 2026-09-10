package io.paritytech.polkadotapp.feature_identity_impl.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext

val BandersnatchContext.Companion.IDENTITY: BandersnatchContext
    get() = BandersnatchContext.fromString("pop:polkadot.network/identity   ")
