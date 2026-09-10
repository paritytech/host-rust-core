package io.paritytech.polkadotapp.feature_coinage_impl.data.transaction

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageInput
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionHash

/** An asset's on-chain identity: a coin's derived account id, or a voucher's ring VRF public key. */
typealias AssetPublicKey = DataByteArray

data class LedgerEntry(
    val id: CoinageTransactionId,
    val groupId: CoinageOperationGroupId?,
    val txHash: TransactionHash,
    val checkpoint: CheckpointBlock,
    val mortalityBlocks: Long,
    val successDetectedAt: CheckpointBlock?,
    val status: CoinageTransactionStatus,
    val inputs: List<LedgerAsset>,
    val outputs: List<LedgerAsset>,
) {
    /** The last block this transaction can still execute in. */
    val mortalityEnd: Long get() = checkpoint.blockNumber + mortalityBlocks
}

enum class CoinageAssetKind { COIN, VOUCHER }

/** [asset] is null for a coin whose key a peer sent us: it has an on-chain identity but no local one. */
data class LedgerAsset(
    val kind: CoinageAssetKind,
    val asset: OwnAsset?,
    val publicKey: AssetPublicKey,
) {
    val isCoin: Boolean get() = kind == CoinageAssetKind.COIN
    val isVoucher: Boolean get() = kind == CoinageAssetKind.VOUCHER
}

data class Verdict(
    val status: CoinageTransactionStatus,
    /** Null clears the record. */
    val successDetectedAt: CheckpointBlock?,
)

enum class WriteOutcome {
    WRITTEN,

    /** A terminal status is never rewritten, so a late event cannot un-fail a failed transaction. */
    DECLINED_TERMINAL,

    /** The status moved while the rules were being evaluated; the next pass re-decides. */
    DECLINED_STALE,
}

data class EntryRegistration(
    val txHash: TransactionHash,
    val checkpoint: CheckpointBlock,
    val mortalityBlocks: Long,
    val groupId: CoinageOperationGroupId?,
    val inputs: List<RegistrationInput>,
    val outputs: List<RegistrationOutput>,
)

data class RegistrationInput(
    val input: CoinageInput,
    val publicKey: AssetPublicKey,
)

data class RegistrationOutput(
    val output: OwnAsset,
    val publicKey: AssetPublicKey,
)
