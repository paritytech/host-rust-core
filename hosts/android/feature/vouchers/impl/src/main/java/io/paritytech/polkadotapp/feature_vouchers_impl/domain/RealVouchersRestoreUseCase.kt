package io.paritytech.polkadotapp.feature_vouchers_impl.domain

import io.novasama.substrate_sdk_android.encrypt.mnemonic.Mnemonic
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.memberKey
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.database.dao.VouchersDao
import io.paritytech.polkadotapp.database.model.VoucherLocal
import io.paritytech.polkadotapp.database.model.VoucherStateLocal
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.AccountSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.requireMetaAccountPassphrase
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherRingPosition
import io.paritytech.polkadotapp.feature_vouchers_api.domain.VouchersRestoreUseCase
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherType
import io.paritytech.polkadotapp.feature_vouchers_impl.data.keysToRing
import io.paritytech.polkadotapp.feature_vouchers_impl.data.privacyVoucher
import timber.log.Timber

private const val MAX_MISSES_IN_ROW = 10

class RealVouchersRestoreUseCase(
    private val knownChains: KnownChains,
    private val remoteStorageSource: StorageDataSource,
    private val secretsStorage: AccountSecretsStorage,
    private val accountRepository: AccountRepository,
    private val vouchersDao: VouchersDao,
) : VouchersRestoreUseCase {
    override suspend fun invoke(): Result<Unit> {
        Timber.d("Starting voucher restoration")

        vouchersDao.removeAllVouchers()

        val candidateMetaId = accountRepository.getCandidateAccount().id

        return remoteStorageSource.queryCatching(knownChains.people) {
            val onChainVouchers = metadata.privacyVoucher.keysToRing.entries()

            Timber.d("Fetched ${onChainVouchers.size} on-chain vouchers")

            val mnemonic = secretsStorage.requireMetaAccountPassphrase(candidateMetaId)
            VoucherType.entries.forEach { restoreForType(mnemonic, it, onChainVouchers) }
        }
    }

    private suspend fun restoreForType(
        mnemonic: Mnemonic,
        voucherType: VoucherType,
        onChainVouchers: Map<BandersnatchPublicKey, PrivacyVoucherRingPosition>
    ) {
        Timber.d("Restoring vouchers of type $voucherType")

        var voucherIndex = 0
        var missedInRow = 0
        var shouldProceed = true

        val restoredVouchers = mutableListOf<VoucherLocal>()

        while (shouldProceed) {
            val memberKey = VoucherEntropyFactory.create(mnemonic, voucherType, voucherIndex).memberKey()
            val onChainVoucherPosition = onChainVouchers[memberKey]

            if (onChainVoucherPosition != null) {
                restoredVouchers.add(
                    VoucherLocal(
                        state = VoucherStateLocal.REGISTERED,
                        type = voucherType.junction,
                        voucherIndex = voucherIndex,
                        value = onChainVoucherPosition.voucherValue.value
                    )
                )

                missedInRow = 0
                voucherIndex++
            } else {
                missedInRow++
                shouldProceed = missedInRow < MAX_MISSES_IN_ROW
            }
        }

        Timber.d("Restored ${restoredVouchers.size} vouchers for type $voucherType")

        vouchersDao.insertVouchers(restoredVouchers)
    }
}
