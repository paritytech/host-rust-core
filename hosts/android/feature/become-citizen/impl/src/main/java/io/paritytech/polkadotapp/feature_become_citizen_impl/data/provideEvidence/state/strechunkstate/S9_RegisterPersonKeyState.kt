package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchSignature
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.common.data.worker.stateMachine.error.TransitionDidNotSucceedException
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getMemberKey
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.sign
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.EvidenceUploadingNonTerminalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.getCurrentCandidate
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicExecutionResult
import io.paritytech.polkadotapp.feature_transactions.api.data.isModuleError
import io.paritytech.polkadotapp.feature_transactions.api.data.isOk
import timber.log.Timber

/**
 * Common errors:
 *
 * **PrivacyVoucher.DepositFailure** - Proof Of Ink Tattoo Reimbursement Pot doesn't have enough balance.
 * Top it up via the configured reimbursement-pot top-up web app (see REFERRAL_WEB_HOST).
 * Note, that account should be topped up in the *PrivacyVoucher.CurrencyLocationInfo* currency
 */

class RegisterPersonKeyState(
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val stateFactory: UploadEvidenceStateFactory
) : EvidenceUploadingNonTerminalState() {
    companion object {
        val ID = "RegisterPerson"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        val candidateAccount = transition.uploadSession.candidateAccount
        val memberKey = bandersnatchSecretsStorage.getMemberKey(transition.uploadSession.candidateAccount.id)

        val provenCandidate = when (val candidate = transition.uploadSession.getCurrentCandidate()) {
            is ProofOfInkCandidate.Proven -> candidate
            // Null state means that we could not track registration tx in the previous run but we have actually registered
            null -> {
                Timber.w("Detected null candidate state - seems like we have missed successfully registration event")

                return Result.success(stateFactory.startPersonSetup())
            }

            else -> throw TransitionDidNotSucceedException("Candidate is not proven yet")
        }

        val ownershipProof = generateProofOfOwnership()

        // TODO DIM1 rewards: specify a separate account as destination
        // Adjust RegisterReferralVouchersWorker to onboard referral rewards into coinage
        // Using the same approach as we use for Game rewards
        val rewardDestination = candidateAccount.defaultAccountId()

        return if (provenCandidate.wasReferred) {
            transition.uploadSession.registerPersonReferred(
                key = memberKey,
                rewardDestination = rewardDestination,
                proofOfOwnership = ownershipProof
            )
        } else {
            transition.uploadSession.registerPersonNonReferred(
                key = memberKey,
                rewardDestination = rewardDestination,
                proofOfOwnership = ownershipProof
            )
        }.mapCatching { executionResult ->
            if (executionResult.canContinue()) {
                stateFactory.startPersonSetup()
            } else {
                throw TransitionDidNotSucceedException(executionResult.outcome.toString())
            }
        }
    }

    context(transition: UploadEvidenceState.Transition)
    private suspend fun generateProofOfOwnership(): BandersnatchSignature {
        val account = transition.uploadSession.candidateAccount
        val accountId = account.accountIdIn(transition.uploadSession.peopleChain)

        val message = transition.uploadSession.generateProofOfOwnershipMessage(accountId)
        return bandersnatchSecretsStorage.sign(account.id, message).toDataByteArray()
    }

    private fun ExtrinsicExecutionResult.canContinue(): Boolean {
        // Attempt to register after successful previous attempt will result in "NotApplied" error
        // https://github.com/paritytech/individuality/blob/132421e16d85535afe570a0a32feaecfb5c8e5f4/substrate/frame/proof-of-ink/src/lib.rs#L518
        return outcome.isOk() || outcome.isModuleError(Modules.PROOF_OF_INK, "NotApplied")
    }
}
