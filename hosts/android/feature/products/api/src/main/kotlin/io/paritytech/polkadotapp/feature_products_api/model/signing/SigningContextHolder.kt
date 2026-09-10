package io.paritytech.polkadotapp.feature_products_api.model.signing

import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SigningContextHolder @Inject constructor() {
    private var context: SigningContext? = null

    fun set(context: SigningContext) {
        this.context = context
    }

    fun get(): SigningContext? = context

    fun clear() {
        context = null
    }
}
