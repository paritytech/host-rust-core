package io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.dataSource

import io.paritytech.polkadotapp.chains.call.RuntimeCallsApi
import io.paritytech.polkadotapp.chains.call.call
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.util.EncodedArguments.Companion.autoEncodedArgs
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.VariableVoucherId

abstract class BaseVoucherValueDataSource : VoucherValueDataSource {
    abstract suspend fun getRuntimeApi(chainId: ChainId): RuntimeCallsApi

    override suspend fun getVariableVoucherValue(
        chainId: ChainId,
        variableVoucherId: VariableVoucherId
    ): Result<Balance> {
        return getRuntimeApi(chainId).getVoucherValue(variableVoucherId)
    }

    private suspend fun RuntimeCallsApi.getVoucherValue(id: VariableVoucherId): Result<Balance> {
        return runCancellableCatching {
            call(
                section = "PrivacyVoucherApi",
                method = "voucher_value",
                arguments = autoEncodedArgs("id" to id)
            )
        }
    }
}
