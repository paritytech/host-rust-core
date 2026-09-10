package io.paritytech.polkadotapp.feature_account_api.domain.model

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext

/**
 * [context] and [derivationPath] are deferred: product-owned contexts and paths that follow a
 * product subtree depend on chain-read values (network suffix, dotNS TLD) that may not be known
 * at DI-graph build time.
 */
class AliasAccountDerivationOverride(
    val context: suspend () -> BandersnatchContext,
    val derivationPath: suspend () -> String
)
