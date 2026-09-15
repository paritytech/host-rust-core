package io.paritytech.polkadotapp.feature_people_api.data.signer.origins

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin

interface PeopleOrigins {
    /**
     * Verifies that the revision of the given alias account is correct and updates it if it is not
     * Returns [TransactionOrigin] once updated. Failure may be returned in case revision actualization failed
     */
    suspend fun asPersonalAliasWithAccountEnsuringRevision(context: BandersnatchContext): Result<TransactionOrigin>
    suspend fun asPersonalAliasWithAccountCreatingAlias(context: BandersnatchContext): Result<TransactionOrigin>

    suspend fun asPersonalAliasWithProof(context: BandersnatchContext): TransactionOrigin

    suspend fun asPersonalIdentityWithProof(): TransactionOrigin

    suspend fun asPersonalIdentityWithAccount(): TransactionOrigin

    /**
     * Authenticates a `Members.self_include` call via a Bandersnatch VRF signature in the
     * `AsMember` transaction extension. The chain expects `RawOrigin::None`, so this origin
     * carries no sender signature.
     */
    suspend fun asMember(): TransactionOrigin
}
