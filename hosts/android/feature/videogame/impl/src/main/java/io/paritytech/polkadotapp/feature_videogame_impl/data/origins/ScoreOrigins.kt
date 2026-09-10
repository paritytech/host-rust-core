package io.paritytech.polkadotapp.feature_videogame_impl.data.origins

import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.SetTransactionExtensionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionSignerSource
import io.paritytech.polkadotapp.feature_videogame_impl.data.extension.ScoreAsParticipantExtension
import javax.inject.Inject

interface ScoreOrigins {
    // Note: this is used both in background and foreground
    // Account for that when changing implementation
    // For example, any fetches should be separated for foreground and background, see
    // PeopleOrigins as an example of complex origins
    suspend fun asAccountParticipant(): TransactionOrigin
}

class RealScoreOrigins @Inject constructor(
    private val accountRepository: AccountRepository,
) : ScoreOrigins {
    override suspend fun asAccountParticipant(): TransactionOrigin {
        val extension = ScoreAsParticipantExtension()
        val metaAccount = accountRepository.getCandidateAccount()
        return SetTransactionExtensionOrigin(TransactionSignerSource.FromAccount(metaAccount), extension)
    }
}
