package io.paritytech.polkadotapp.feature_people_api.domain.invitation

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount

interface InvitationService {
    suspend fun issueInvitation(chain: Chain, invitee: MetaAccount, dim: DimName): IssueInvitationResult
}

sealed interface IssueInvitationResult {
    data class Success(val consumable: ConsumableInvitation) : IssueInvitationResult

    data object AlreadyUsed : IssueInvitationResult

    data object Unavailable : IssueInvitationResult

    data object BackendUnavailable : IssueInvitationResult

    data class Failed(val error: Throwable) : IssueInvitationResult
}

interface ConsumableInvitation {
    suspend fun <R> tryConsume(consume: suspend (IssuedInvitation) -> Result<R>): Result<R>
}
