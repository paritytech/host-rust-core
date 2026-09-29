package io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.dataSource

import io.paritytech.polkadotapp.chains.call.MultiChainRuntimeCallsApi
import io.paritytech.polkadotapp.chains.call.RuntimeCallsApi
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import javax.inject.Inject

class ForegroundVoucherValueDataSource @Inject constructor(
    private val multiChainRuntimeCallsApi: MultiChainRuntimeCallsApi,
) : BaseVoucherValueDataSource() {
    override suspend fun getRuntimeApi(chainId: ChainId): RuntimeCallsApi {
        return multiChainRuntimeCallsApi.forChain(chainId)
    }
}
