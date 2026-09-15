package io.paritytech.polkadotapp.feature_revive_impl.data

import io.paritytech.polkadotapp.chains.call.MultiChainRuntimeCallsApi
import io.paritytech.polkadotapp.chains.call.call
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.WeightV2
import io.paritytech.polkadotapp.chains.network.binding.mapError
import io.paritytech.polkadotapp.chains.network.binding.toDispatchError
import io.paritytech.polkadotapp.chains.network.binding.toResult
import io.paritytech.polkadotapp.chains.util.EncodedArguments.Companion.autoEncodedArgs
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.padEnd
import io.paritytech.polkadotapp.feature_revive_api.EvmAccountId
import io.paritytech.polkadotapp.feature_revive_api.ReviveContractApi
import javax.inject.Inject

class RealReviveContractApi @Inject constructor(
    private val multiChainRuntimeCallsApi: MultiChainRuntimeCallsApi,
) : ReviveContractApi {
    override suspend fun callReadOnly(
        chainId: ChainId,
        contract: EvmAccountId,
        input: DataByteArray,
    ): Result<DataByteArray> {
        val runtimeCallsApi = multiChainRuntimeCallsApi.forChain(chainId)
        val runtime = runtimeCallsApi.runtime

        return runCatching<ReviveContractResult> {
            runtimeCallsApi.call(
                section = "ReviveApi",
                method = "call",
                arguments = autoEncodedArgs(
                    "origin" to reviveOriginAccount(),
                    "dest" to contract,
                    "value" to 0,
                    "gas_limit" to WeightV2.max(),
                    "storage_deposit_limit" to WeightV2.MAX_DIMENSION,
                    "input_data" to input,
                )
            )
        }.flatMap { contractResult ->
            contractResult.result
                .mapError { it.toDispatchError(runtime) }
                .toResult()
        }.map { it.data }
    }

    private fun reviveOriginAccount(): AccountId {
        return "modlpy/reviv".encodeToByteArray().padEnd(32).intoAccountId()
    }
}
