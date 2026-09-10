package io.paritytech.polkadotapp.feature_revive_api

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import org.bouncycastle.jcajce.provider.digest.Keccak

typealias EvmAccountId = DataByteArray

interface ReviveContractApi {
    suspend fun callReadOnly(
        chainId: ChainId,
        contract: EvmAccountId,
        input: DataByteArray,
    ): Result<DataByteArray>
}

/**
 * Maps a Substrate AccountId32 to its pallet-revive H160 AccountId.
 *
 * pallet-revive's default `AccountIdMapper` derives the EVM AccountId as
 * the last 20 bytes of `keccak256(accountId)` (see runtime `pallet-revive`).
 */
fun AccountId.toEvmAccountId(): EvmAccountId {
    val keccak = Keccak.Digest256().digest(value)
    return keccak.copyOfRange(12, 32).toDataByteArray()
}
