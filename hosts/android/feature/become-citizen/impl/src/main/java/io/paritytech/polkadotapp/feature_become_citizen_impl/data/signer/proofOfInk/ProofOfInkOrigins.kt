package io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk

import io.paritytech.polkadotapp.feature_become_citizen_api.data.signer.PostApplyOriginProvider
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin

interface ProofOfInkOrigins : PostApplyOriginProvider {
    suspend fun applyWithSignatureOrigin(): TransactionOrigin

    suspend fun applyWithInvitationOrigin(): TransactionOrigin

    suspend fun applyWithDepositOrigin(): TransactionOrigin
}
