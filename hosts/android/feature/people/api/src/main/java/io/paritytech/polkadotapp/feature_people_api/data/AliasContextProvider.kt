package io.paritytech.polkadotapp.feature_people_api.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext

fun interface AliasContextProvider {
    suspend fun context(): BandersnatchContext
}
