package io.paritytech.polkadotapp.feature_vouchers_impl.data.signer.origin

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.SetTransactionExtensionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionSignerSource
import io.paritytech.polkadotapp.feature_vouchers_impl.data.PRIVACY_VOUCHER
import io.paritytech.polkadotapp.feature_vouchers_impl.data.signer.extension.ProvideForVoucherClaimer

interface PrivacyVoucherOrigins {
    suspend fun voucherClaimer(): TransactionOrigin
}

class RealPrivacyVoucherOrigins(
    private val accountRepository: AccountRepository
) : PrivacyVoucherOrigins {
    override suspend fun voucherClaimer(): TransactionOrigin {
        val aliasAccount = accountRepository.getAliasAccount(BandersnatchContext.PRIVACY_VOUCHER)
        return SetTransactionExtensionOrigin(
            signerSource = TransactionSignerSource.FromAccount(aliasAccount),
            transactionExtension = ProvideForVoucherClaimer(),
        )
    }
}
