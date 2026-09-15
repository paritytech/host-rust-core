package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_account_api.domain.derivation.DerivationIndex32
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTld
import io.paritytech.polkadotapp.feature_products_api.domain.accountsProtocol.ProductProofContext
import io.paritytech.polkadotapp.feature_products_api.model.derivation.ReservedProductIds

private const val SCORE_INDEX = 0u

/**
 * Score's context allocation inside the personhood product, matching `personhood::SCORE` on chain.
 * The alias account is derived from this very context, so both must keep the same suffix or the
 * account no longer maps 1:1 to the alias it proves.
 */
fun scorePersonhoodContext(tld: DotNsTld): ProductProofContext {
    return ProductProofContext(
        productId = ReservedProductIds.personhood(tld),
        suffix = DerivationIndex32.fromUInt(SCORE_INDEX),
    )
}

internal fun BandersnatchContext.Companion.score(tld: DotNsTld): BandersnatchContext {
    return scorePersonhoodContext(tld).productContextBytes()
}
