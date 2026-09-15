package io.paritytech.polkadotapp.feature_web3summit_impl.data.contract

import io.novasama.substrate_sdk_android.extensions.fromHex
import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_revive_api.ReviveContractApi
import io.paritytech.polkadotapp.feature_revive_api.toEvmAccountId
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitConfigProvider
import org.web3j.abi.FunctionEncoder
import org.web3j.abi.FunctionReturnDecoder
import org.web3j.abi.TypeReference
import org.web3j.abi.datatypes.Address
import org.web3j.abi.datatypes.Bool
import org.web3j.abi.datatypes.Function
import org.web3j.abi.datatypes.Type
import javax.inject.Inject

class RealWeb3SummitContractRepository @Inject constructor(
    private val reviveContractApi: ReviveContractApi,
    private val configProvider: Web3SummitConfigProvider,
    private val chainRegistry: ChainRegistry,
) : Web3SummitContractRepository {
    override suspend fun isCheckedIn(productAccountId: AccountId): Result<Boolean> {
        val evmAccountId = productAccountId.toEvmAccountId()
        val input = encodeIsCheckedIn(evmAccountId.value)
        return configProvider.getConfig().flatMap { config ->
            reviveContractApi.callReadOnly(
                chainId = chainRegistry.knownChains.assetHub,
                contract = config.contractAddress,
                input = input.toDataByteArray(),
            ).mapCatching { decodeBool(it.value) }
        }.logFailure("Failed to query isCheckedIn")
    }

    private fun encodeIsCheckedIn(evmAddress: ByteArray): ByteArray {
        val function = Function(
            "isCheckedIn",
            listOf<Type<*>>(Address(evmAddress.toHexString(withPrefix = true))),
            listOf(boolOutputRef),
        )
        return FunctionEncoder.encode(function).fromHex()
    }

    private fun decodeBool(output: ByteArray): Boolean {
        if (output.isEmpty()) return false
        val decoded = FunctionReturnDecoder.decode(output.toHexString(withPrefix = true), listOf(boolOutputRef))
        return (decoded.firstOrNull() as? Bool)?.value == true
    }

    @Suppress("UNCHECKED_CAST")
    private val boolOutputRef = object : TypeReference<Bool>() {} as TypeReference<Type<*>>
}
