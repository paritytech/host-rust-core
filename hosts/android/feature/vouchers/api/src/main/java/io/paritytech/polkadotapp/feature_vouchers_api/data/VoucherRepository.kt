package io.paritytech.polkadotapp.feature_vouchers_api.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchRingMembers
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherRingPosition
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherState
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherType
import kotlinx.coroutines.flow.Flow

interface VoucherRepository {
    suspend fun createVoucher(candidateMetaId: Long, index: Int, type: VoucherType): Voucher
    suspend fun generateNextVoucher(candidateMetaId: Long, type: VoucherType): Voucher
    suspend fun removeVoucher(voucher: Voucher)

    suspend fun getAllVouchers(candidateMetaId: Long): List<Voucher>
    fun subscribeAllVouchers(candidateMetaId: Long): Flow<List<Voucher>>
    suspend fun getVouchersByType(candidateMetaId: Long, type: VoucherType): List<Voucher>
    suspend fun getVouchersByState(candidateMetaId: Long, state: VoucherState): List<Voucher>

    suspend fun getVoucherRingPositions(
        chainId: String,
        voucherIds: Collection<BandersnatchPublicKey>
    ): Result<Map<BandersnatchPublicKey, PrivacyVoucherRingPosition>>

    suspend fun getRingMembers(
        chainId: String,
        positions: Collection<PrivacyVoucherRingPosition>,
    ): Result<Map<PrivacyVoucherRingPosition, BandersnatchRingMembers>>
}

suspend fun VoucherRepository.removeVouchers(vouchers: List<Voucher>) {
    vouchers.forEach { removeVoucher(it) }
}
