package io.paritytech.polkadotapp.feature_revive_impl.data

import io.paritytech.polkadotapp.chains.network.binding.DynamicDispatchError
import io.paritytech.polkadotapp.chains.network.binding.ScaleResult
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import kotlinx.serialization.Serializable

/**
 * Minimal model for the Revive pallet `ContractResult` return type.
 *
 * The full on-chain type has many fields (gas_consumed, gas_required, storage_deposit, etc.)
 * but we only need the `result` field which contains the EVM execution outcome.
 * The dynamic SCALE format ignores fields not declared in the model.
 */
@Serializable
class ReviveContractResult(
    val result: ScaleResult<ExecReturnValue, DynamicDispatchError>
)

@Serializable
class ExecReturnValue(
    val data: DataByteArray
)
