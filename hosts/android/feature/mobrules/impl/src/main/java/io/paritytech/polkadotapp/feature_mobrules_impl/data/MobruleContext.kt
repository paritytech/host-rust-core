package io.paritytech.polkadotapp.feature_mobrules_impl.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext

val BandersnatchContext.Companion.MOB_RULE: BandersnatchContext
    get() = BandersnatchContext.fromString("pop:polkadot.network/mob-rule   ")
