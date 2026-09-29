package io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.VariableVoucherId
import io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.dataSource.VoucherValueDataSource

interface VoucherValueRepository {
    suspend fun getVariableVoucherValue(
        chainId: ChainId,
        variableVoucherId: VariableVoucherId
    ): Result<Balance>
}

class RealVoucherValueRepository(
    private val dataSource: VoucherValueDataSource,
) : VoucherValueRepository {
    override suspend fun getVariableVoucherValue(
        chainId: ChainId,
        variableVoucherId: VariableVoucherId
    ): Result<Balance> {
        return dataSource.getVariableVoucherValue(chainId, variableVoucherId)
    }
}
