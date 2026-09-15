package io.paritytech.polkadotapp.feature_vouchers_impl.data

import io.novasama.substrate_sdk_android.encrypt.mnemonic.Mnemonic
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchEntropy
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchRingMembers
import io.paritytech.polkadotapp.bandersnatch_crypto.aliasInContext
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.network.binding.intoBalance
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.database.dao.VouchersDao
import io.paritytech.polkadotapp.database.model.VoucherLocal
import io.paritytech.polkadotapp.database.model.VoucherStateLocal
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.AccountSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.requireMetaAccountPassphrase
import io.paritytech.polkadotapp.feature_vouchers_api.data.VoucherRepository
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherRingPosition
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.toParts
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherState
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherType
import io.paritytech.polkadotapp.feature_vouchers_impl.data.mappers.toDomain
import io.paritytech.polkadotapp.feature_vouchers_impl.data.mappers.toLocal
import io.paritytech.polkadotapp.feature_vouchers_impl.domain.VoucherEntropyFactory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.math.BigInteger
import javax.inject.Inject

interface VoucherInternalRepository : VoucherRepository {
    suspend fun updateVoucherState(index: Int, type: VoucherType, newState: VoucherState)
}

class RealVoucherRepository @Inject constructor(
    private val secretsStorage: AccountSecretsStorage,
    private val vouchersDao: VouchersDao,
    @RemoteSourceQualifier private val remoteStorageSource: StorageDataSource
) : VoucherInternalRepository, VoucherRepository {
    override suspend fun createVoucher(candidateMetaId: Long, index: Int, type: VoucherType): Voucher {
        return generateAndStoreVoucher(
            localType = type.junction,
            index = index,
            candidateMetaId = candidateMetaId
        )
    }

    override suspend fun generateNextVoucher(candidateMetaId: Long, type: VoucherType): Voucher {
        val localType = type.junction
        val nextIndex = vouchersDao.getNextIndexForType(localType)

        return generateAndStoreVoucher(
            localType = localType,
            index = nextIndex,
            candidateMetaId = candidateMetaId
        )
    }

    override suspend fun removeVoucher(voucher: Voucher) {
        vouchersDao.removeVoucher(
            index = voucher.index,
            type = voucher.type.junction
        )
    }

    override suspend fun getAllVouchers(candidateMetaId: Long): List<Voucher> {
        return createDomainVouchers(candidateMetaId) {
            vouchersDao.getAllVouchers()
        }
    }

    override fun subscribeAllVouchers(candidateMetaId: Long): Flow<List<Voucher>> {
        return vouchersDao.allVouchersFlow()
            .map { vouchersList ->
                createDomainVouchers(candidateMetaId) { vouchersList }
            }
    }

    override suspend fun getVouchersByType(candidateMetaId: Long, type: VoucherType): List<Voucher> {
        return createDomainVouchers(candidateMetaId) {
            vouchersDao.getVouchersByType(type.junction)
        }
    }

    override suspend fun getVouchersByState(candidateMetaId: Long, state: VoucherState): List<Voucher> {
        return createDomainVouchers(candidateMetaId) {
            vouchersDao.getVouchersByState(state.toLocal())
        }
    }

    override suspend fun getVoucherRingPositions(
        chainId: String,
        voucherIds: Collection<BandersnatchPublicKey>
    ): Result<Map<BandersnatchPublicKey, PrivacyVoucherRingPosition>> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.privacyVoucher.keysToRing.entries(voucherIds)
        }
    }

    override suspend fun getRingMembers(
        chainId: String,
        positions: Collection<PrivacyVoucherRingPosition>,
    ): Result<Map<PrivacyVoucherRingPosition, BandersnatchRingMembers>> {
        return remoteStorageSource.queryCatching(chainId) {
            val positionArgs = positions.map { it.toParts() }

            metadata.privacyVoucher.keys.entries(positionArgs)
                .mapKeys { (keyArgs, _) -> PrivacyVoucherRingPosition(keyArgs.first, keyArgs.second) }
        }
    }

    override suspend fun updateVoucherState(index: Int, type: VoucherType, newState: VoucherState) {
        vouchersDao.updateVoucherState(index, type.junction, newState.toLocal())
    }

    private suspend fun createDomainVouchers(
        candidateMetaId: Long,
        voucherProvider: suspend () -> List<VoucherLocal>
    ): List<Voucher> {
        val mnemonic = secretsStorage.requireMetaAccountPassphrase(candidateMetaId)
        return voucherProvider().map { it.toDomain(mnemonic) }
    }

    private suspend fun generateAndStoreVoucher(
        localType: String,
        index: Int,
        candidateMetaId: Long
    ): PrecomputedVoucher {
        val voucherLocal = VoucherLocal(
            state = VoucherStateLocal.GENERATED,
            type = localType,
            voucherIndex = index,
            value = BigInteger.ZERO
        )

        vouchersDao.insertVoucher(voucherLocal)

        return voucherLocal.toDomain(secretsStorage.requireMetaAccountPassphrase(candidateMetaId))
    }

    private fun VoucherLocal.toDomain(mnemonic: Mnemonic) = PrecomputedVoucher(mnemonic = mnemonic, local = this)

    private inner class PrecomputedVoucher(mnemonic: Mnemonic, local: VoucherLocal) : Voucher {
        override val index = local.voucherIndex
        override val type = VoucherType.fromJunction(local.type)
        override val state = local.state.toDomain()
        override val value = local.value.intoBalance() // todo: rework token amount classes

        override val entropy: BandersnatchEntropy by lazy(LazyThreadSafetyMode.NONE) {
            VoucherEntropyFactory.create(mnemonic, type, index)
        }
        override val alias: BandersnatchAlias by lazy(LazyThreadSafetyMode.NONE) {
            entropy.aliasInContext(BandersnatchContext.PRIVACY_VOUCHER)
        }
    }
}
