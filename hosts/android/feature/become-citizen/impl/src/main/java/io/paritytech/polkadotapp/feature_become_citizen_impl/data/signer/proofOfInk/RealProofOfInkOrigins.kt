package io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.isInvited
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.isReferred
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.datasource.ProofOfInkOriginsDataSource
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.referral.AsProofOfInkParticipant
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.SetTransactionExtensionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionSignerSource
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.asSignedOrigin
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.referral.AsProofOfInkParticipant.Variant as PoIParticipantVariant

class RealProofOfInkOrigins(
    private val accountRepository: AccountRepository,
    private val dataSource: ProofOfInkOriginsDataSource,
) : ProofOfInkOrigins {
    override suspend fun applyWithSignatureOrigin(): TransactionOrigin {
        val candidate = accountRepository.getCandidateAccount()
        return asPoIParticipantOrigin(candidate, PoIParticipantVariant.AS_APPLY_WITH_SIG)
    }

    override suspend fun applyWithInvitationOrigin(): TransactionOrigin {
        val candidate = accountRepository.getCandidateAccount()
        return asPoIParticipantOrigin(candidate, PoIParticipantVariant.AS_INVITED)
    }

    override suspend fun applyWithDepositOrigin(): TransactionOrigin {
        return accountRepository.getCandidateAccount().asSignedOrigin()
    }

    override suspend fun postApplyOrigin(chain: Chain): TransactionOrigin {
        val account = accountRepository.getCandidateAccount()
        val accountId = account.accountIdIn(chain)
        val candidateState = dataSource.getCandidateState(chain.id, accountId)

        return when {
            candidateState.wasReferred() -> asPoIParticipantOrigin(account, PoIParticipantVariant.AS_REFERRED)
            candidateState.wasInvited() -> asPoIParticipantOrigin(account, PoIParticipantVariant.AS_INVITED)
            else -> account.asSignedOrigin()
        }
    }

    private fun asPoIParticipantOrigin(
        candidateAccount: MetaAccount,
        variant: PoIParticipantVariant
    ): TransactionOrigin {
        val extension = AsProofOfInkParticipant(variant)
        return SetTransactionExtensionOrigin(TransactionSignerSource.FromAccount(candidateAccount), extension)
    }

    private fun ProofOfInkCandidate?.wasInvited(): Boolean {
        return when (this) {
            is ProofOfInkCandidate.Applied -> credibility.isInvited()
            is ProofOfInkCandidate.Selected -> credibility.isInvited()
            is ProofOfInkCandidate.Proven -> wasInvited

            ProofOfInkCandidate.Unknown, null -> false
        }
    }

    private fun ProofOfInkCandidate?.wasReferred(): Boolean {
        return when (this) {
            is ProofOfInkCandidate.Applied -> credibility.isReferred()
            is ProofOfInkCandidate.Selected -> credibility.isReferred()
            is ProofOfInkCandidate.Proven -> wasReferred

            ProofOfInkCandidate.Unknown, null -> false
        }
    }
}
