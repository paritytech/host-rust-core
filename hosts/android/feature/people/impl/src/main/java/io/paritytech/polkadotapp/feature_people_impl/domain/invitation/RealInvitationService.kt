package io.paritytech.polkadotapp.feature_people_impl.domain.invitation

import io.novasama.substrate_sdk_android.encrypt.EncryptionType
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.MultiSignature
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.util.accountIdOf
import io.paritytech.polkadotapp.chains.util.addressOf
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_people_api.data.storage.InvitationStorage
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.ConsumableInvitation
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.DimName
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.InvitationService
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssueInvitationResult
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import io.paritytech.polkadotapp.feature_people_impl.data.network.InvitationTicketNetworkApi
import io.paritytech.polkadotapp.feature_people_impl.data.network.model.DimTicketRequest
import io.paritytech.polkadotapp.feature_people_impl.data.network.model.DimTicketResponse
import retrofit2.HttpException
import timber.log.Timber
import java.io.IOException
import javax.inject.Inject

internal class RealInvitationService @Inject constructor(
    private val api: InvitationTicketNetworkApi,
    private val storage: InvitationStorage,
) : InvitationService {
    override suspend fun issueInvitation(
        chain: Chain,
        invitee: MetaAccount,
        dim: DimName,
    ): IssueInvitationResult {
        storage.getIssuedInvitation(dim)?.let { cached ->
            return IssueInvitationResult.Success(consumable(cached, dim))
        }

        val whoAddress = chain.addressOf(invitee.accountIdIn(chain))
        return runCancellableCatching {
            api.issueDimTicket(DimTicketRequest(who = whoAddress, dim = dim.value))
        }.fold(
            onSuccess = { dto ->
                val invitation = dto.toIssuedInvitation(dim, invitee, chain)
                storage.setIssuedInvitation(invitation)
                IssueInvitationResult.Success(consumable(invitation, dim))
            },
            onFailure = { error ->
                Timber.e(error, "Failed to obtain dim ticket")
                error.toIssueInvitationResult()
            }
        )
    }

    private fun consumable(invitation: IssuedInvitation, dim: DimName): ConsumableInvitation =
        object : ConsumableInvitation {
            override suspend fun <R> tryConsume(
                consume: suspend (IssuedInvitation) -> Result<R>,
            ): Result<R> {
                return consume(invitation).onSuccess { storage.clearIssuedInvitation(dim) }
            }
        }
}

private fun DimTicketResponse.toIssuedInvitation(
    dim: DimName,
    invitee: MetaAccount,
    chain: Chain,
): IssuedInvitation {
    val inviterId = chain.accountIdOf(inviter)
    val ticket = chain.accountIdOf(publicKey.fromHex())
    val multiSignature = MultiSignature(EncryptionType.SR25519, signature.fromHex())

    return IssuedInvitation(
        invitee = invitee,
        inviter = inviterId,
        ticket = ticket,
        signature = multiSignature,
        dim = dim,
    )
}

private fun Throwable.toIssueInvitationResult(): IssueInvitationResult = when {
    this is HttpException && code() == 409 -> IssueInvitationResult.AlreadyUsed
    this is HttpException && code() == 503 -> IssueInvitationResult.Unavailable
    this is HttpException && code() == 401 -> IssueInvitationResult.Failed(this)
    this is HttpException && code() in 500..599 -> IssueInvitationResult.BackendUnavailable
    this is IOException -> IssueInvitationResult.BackendUnavailable
    else -> IssueInvitationResult.Failed(this)
}
