package io.paritytech.polkadotapp.feature_mobrules_impl.data.signer.origin

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import javax.inject.Inject

interface VotingOrigins {
    suspend fun mobRuleOrigin(): Result<TransactionOrigin>
}

class RealVotingOrigins @Inject constructor(
    private val peopleOrigins: PeopleOrigins,
) : VotingOrigins {
    override suspend fun mobRuleOrigin(): Result<TransactionOrigin> {
        return peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(BandersnatchContext.MOB_RULE)
    }
}
