package io.paritytech.polkadotapp.feature_products_impl.domain.bot.e2e

import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class E2ERuntimeMarkers @Inject constructor() {
    @Volatile
    var enabled: Boolean = false
}
