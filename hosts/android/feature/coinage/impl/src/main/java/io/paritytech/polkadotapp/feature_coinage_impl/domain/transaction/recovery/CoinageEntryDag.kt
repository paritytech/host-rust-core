package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery

import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.AssetPublicKey
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerEntry

/**
 * One pass's snapshot of the entry graph, indexed so the rules read fields instead of running queries.
 *
 * Entries are never deleted, so the whole ledger is the graph: outputs of some entries are inputs of others.
 * Statuses are the ones read when the snapshot was taken; the verdict write re-checks them, so a stale
 * snapshot can only cost a verdict, never produce a wrong one.
 */
class CoinageEntryDag(
    val entries: List<LedgerEntry>,
    private val handedOffKeys: Set<AssetPublicKey>,
) {
    private val minterByKey: Map<AssetPublicKey, LedgerEntry> =
        entries.flatMap { entry -> entry.outputs.map { it.publicKey to entry } }.toMap()

    private val consumersByKey: Map<AssetPublicKey, List<LedgerEntry>> =
        entries.flatMap { entry -> entry.inputs.map { it.publicKey to entry } }
            .groupBy({ it.first }, { it.second })

    fun minter(key: AssetPublicKey): LedgerEntry? = minterByKey[key]

    /** Entries that record [key] as one of their inputs, whatever their status. */
    fun consumers(key: AssetPublicKey): List<LedgerEntry> = consumersByKey[key].orEmpty()

    /** Entries consuming an output of [entry]. */
    fun successors(entry: LedgerEntry): List<LedgerEntry> =
        entry.outputs.flatMap { consumersByKey[it.publicKey].orEmpty() }.distinctBy { it.id }

    fun isHandedOff(key: AssetPublicKey): Boolean = key in handedOffKeys
}
