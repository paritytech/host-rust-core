package io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.dataSource

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.VariableVoucherId

interface VoucherValueDataSource {
    suspend fun getVariableVoucherValue(
        chainId: ChainId,
        variableVoucherId: VariableVoucherId
    ): Result<Balance>
}
