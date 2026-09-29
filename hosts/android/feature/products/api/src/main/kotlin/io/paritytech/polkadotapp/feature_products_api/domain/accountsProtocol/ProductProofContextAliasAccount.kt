package io.paritytech.polkadotapp.feature_products_api.domain.accountsProtocol

import io.paritytech.polkadotapp.feature_products_api.model.derivation.productAccountPath

/**
 * RFC-0004 `product_account_id_for_proof_context`: a context's alias account is the owning product's
 * account at the context suffix, 1:1. Every context has exactly one owner, so no per-context
 * override is needed to place its alias account.
 */
fun ProductProofContext.aliasAccountDerivationPath(): String = productAccountPath(productId, suffix)
