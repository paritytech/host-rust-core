package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.requireNotNull
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.applyWithSignature
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.ProofOfInkReferralsRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.ReferralApplyUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketOrigin
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.ProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure

class RealReferralApplyUseCase(
    private val proofOfInkReferralsRepository: ProofOfInkReferralsRepository,
    private val accountRepository: AccountRepository,
    private val extrinsicService: ExtrinsicService,
    private val chainRegistry: ChainRegistry,
    private val proofOfInkOriginsFactory: ProofOfInkOriginsFactory
) : ReferralApplyUseCase {
    override suspend fun hasSavedReferralTicket(): Boolean {
        return proofOfInkReferralsRepository.hasSavedTicket(ReferralTicketOrigin.REFEREE)
    }

    override suspend fun applyReferral(): Result<Unit> {
        val chain = chainRegistry.peopleChain()
        val candidateAccountId = accountRepository.getCandidateAccount().accountIdIn(chain)

        return proofOfInkReferralsRepository
            .getSavedTicket(ReferralTicketOrigin.REFEREE)
            .requireNotNull()
            .flatMap { referralTicket ->
                extrinsicService.submitExtrinsicAndAwaitExecution(
                    chain = chain,
                    origin = proofOfInkOriginsFactory.foreground.applyWithSignatureOrigin()
                ) {
                    proofOfInk.applyWithSignature(
                        referrer = referralTicket.referrer.id,
                        signature = referralTicket.createReferralSignature(candidateAccountId),
                        ticket = referralTicket.toPublic()
                    )
                }
                    .flattenExecutionFailure()
                    .coerceToUnit()
            }
    }
}
