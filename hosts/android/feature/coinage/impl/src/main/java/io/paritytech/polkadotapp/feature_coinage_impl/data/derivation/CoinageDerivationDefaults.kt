package io.paritytech.polkadotapp.feature_coinage_impl.data.derivation

object CoinageDerivationDefaults {
    // RFC-0017 shapes coinage derivations as `<root>//<purse>//<page>//<item>`. We only ever derive into the main purse,
    // which the RFC pins to `u32::MAX` so that the randomly assigned product-purse ids can never collide with it.
    const val COINAGE_MAIN_PURSE_INDEX = 4_294_967_295L

    // The RFC leaves paging unspecified beyond the path shape, so we stay on the first page.
    const val COINAGE_PAGE_INDEX = 0
}
