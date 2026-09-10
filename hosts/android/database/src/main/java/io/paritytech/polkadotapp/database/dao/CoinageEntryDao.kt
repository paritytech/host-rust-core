package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Relation
import androidx.room.Transaction
import io.paritytech.polkadotapp.database.model.CoinageEntryInputLocal
import io.paritytech.polkadotapp.database.model.CoinageEntryLocal
import io.paritytech.polkadotapp.database.model.CoinageEntryOutputLocal
import io.paritytech.polkadotapp.database.model.CoinageHandoffLocal
import kotlinx.coroutines.flow.Flow

private const val LIVE_STATUSES = "('PENDING', 'PENDING_SUCCESS')"

/**
 * Every asset this subsystem knows anything about, with its lock and the status of the entry minting it.
 *
 * The key space is the union of everything that can carry either fact; each fact is then a correlated
 * lookup, which keeps this one query rather than three that could observe different snapshots.
 */
private const val ASSET_STATE_QUERY = """
    SELECT k.assetKind AS assetKind,
           k.derivationIndex AS derivationIndex,
           (
               SELECT e.status FROM coinage_entry_output o
               JOIN coinage_entry e ON e.id = o.entryId
               WHERE o.assetKind = k.assetKind AND o.derivationIndex = k.derivationIndex
               LIMIT 1
           ) AS minterStatus,
           EXISTS(
               SELECT 1 FROM coinage_handoff h
               WHERE h.assetKind = k.assetKind AND h.derivationIndex = k.derivationIndex
           ) AS handedOff,
           (
               SELECT e2.status FROM coinage_entry_input i
               JOIN coinage_entry e2 ON e2.id = i.entryId
               WHERE i.assetKind = k.assetKind AND i.derivationIndex = k.derivationIndex
                 AND e2.status != 'FAILURE'
               LIMIT 1
           ) AS consumerStatus
    FROM (
        SELECT assetKind, derivationIndex FROM coinage_entry_output
        UNION
        SELECT assetKind, derivationIndex FROM coinage_entry_input WHERE derivationIndex IS NOT NULL
        UNION
        SELECT assetKind, derivationIndex FROM coinage_handoff
    ) k
"""

@Dao
abstract class CoinageEntryDao {
    /** Runs [action] in one database transaction. */
    @Transaction
    open suspend fun withTransaction(action: suspend () -> Unit) {
        return action()
    }

    /** Returns the id SQLite assigned, which is also this entry's place in registration order. */
    @Transaction
    open suspend fun insertEntry(
        entry: CoinageEntryLocal,
        inputs: (entryId: Long) -> List<CoinageEntryInputLocal>,
        outputs: (entryId: Long) -> List<CoinageEntryOutputLocal>,
    ): Long {
        val id = insert(entry)
        insertInputs(inputs(id))
        insertOutputs(outputs(id))

        return id
    }

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract suspend fun insert(entry: CoinageEntryLocal): Long

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract suspend fun insertInputs(inputs: List<CoinageEntryInputLocal>)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract suspend fun insertOutputs(outputs: List<CoinageEntryOutputLocal>)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    abstract suspend fun insertHandoffs(handoffs: List<CoinageHandoffLocal>)

    // ---- invariant support, one batched query each ----

    /** Of [onChainKeys], those already minted by some entry. */
    @Query("SELECT onChainKey FROM coinage_entry_output WHERE onChainKey IN (:onChainKeys)")
    abstract suspend fun filterMinted(onChainKeys: List<ByteArray>): List<ByteArray>

    /** Of [onChainKeys], those that are a key a peer sent us. */
    @Query(
        """
        SELECT onChainKey FROM coinage_entry_input
        WHERE onChainKey IN (:onChainKeys) AND derivationIndex IS NULL
        """
    )
    abstract suspend fun filterReceivedKeys(onChainKeys: List<ByteArray>): List<ByteArray>

    /** Of [onChainKeys], those already claimed by an entry that has not failed. */
    @Query(
        """
        SELECT i.onChainKey FROM coinage_entry_input i
        JOIN coinage_entry e ON e.id = i.entryId
        WHERE i.onChainKey IN (:onChainKeys) AND e.status != 'FAILURE'
        """
    )
    abstract suspend fun filterClaimed(onChainKeys: List<ByteArray>): List<ByteArray>

    /** Of [onChainKeys], those whose key has left the device. */
    @Query("SELECT onChainKey FROM coinage_handoff WHERE onChainKey IN (:onChainKeys)")
    abstract suspend fun filterHandedOff(onChainKeys: List<ByteArray>): List<ByteArray>

    // ---- status ----

    @Query("SELECT status FROM coinage_entry WHERE id = :id")
    abstract suspend fun getStatus(id: Long): CoinageEntryLocal.Status?

    @Query("SELECT status FROM coinage_entry WHERE id = :id")
    abstract fun subscribeStatus(id: Long): Flow<CoinageEntryLocal.Status?>

    /** Returns the number of rows written: 0 means the entry no longer reads [expected]. */
    @Query(
        """
        UPDATE coinage_entry
        SET status = :status,
            successDetectedblockNumber = :successDetectedBlockNumber,
            successDetectedblockHash = :successDetectedBlockHash
        WHERE id = :id AND status = :expected
        """
    )
    abstract suspend fun compareAndSetStatus(
        id: Long,
        expected: CoinageEntryLocal.Status,
        status: CoinageEntryLocal.Status,
        successDetectedBlockNumber: Long?,
        successDetectedBlockHash: String?,
    ): Int

    // ---- reads ----

    @Transaction
    @Query("SELECT * FROM coinage_entry WHERE id = :id")
    abstract suspend fun getEntry(id: Long): CoinageEntryWithAssets?

    @Transaction
    @Query("SELECT * FROM coinage_entry ORDER BY id ASC")
    abstract suspend fun getAllEntries(): List<CoinageEntryWithAssets>

    @Query("SELECT * FROM coinage_handoff")
    abstract suspend fun getHandoffs(): List<CoinageHandoffLocal>

    @Query("UPDATE coinage_handoff SET committed = 1 WHERE onChainKey IN (:onChainKeys)")
    abstract suspend fun commitHandoffs(onChainKeys: List<ByteArray>)

    /**
     * A provisional mark belongs to a payment that never became durable, so its keys never left. Clearing it
     * on launch is what returns those assets; a committed mark is never touched.
     */
    @Query("DELETE FROM coinage_handoff WHERE committed = 0")
    abstract suspend fun deleteUncommittedHandoffs()

    @Query("SELECT EXISTS(SELECT 1 FROM coinage_entry WHERE status IN $LIVE_STATUSES)")
    abstract suspend fun hasLiveEntries(): Boolean

    // ---- derived views ----

    @Transaction
    @Query("SELECT * FROM coinage_entry WHERE operationGroupId = :groupId ORDER BY id ASC")
    abstract suspend fun getGroupEntries(groupId: String): List<CoinageEntryWithAssets>

    @Transaction
    @Query("SELECT * FROM coinage_entry WHERE operationGroupId = :groupId ORDER BY id ASC")
    abstract fun subscribeGroupEntries(groupId: String): Flow<List<CoinageEntryWithAssets>>

    @Query(ASSET_STATE_QUERY)
    abstract fun subscribeAssetStates(): Flow<List<CoinageAssetStateProjection>>

    @Query("$ASSET_STATE_QUERY WHERE k.assetKind = :assetKind AND k.derivationIndex = :derivationIndex")
    abstract suspend fun getAssetState(
        assetKind: CoinageEntryLocal.AssetKind,
        derivationIndex: Int,
    ): CoinageAssetStateProjection?

    /** One kind at a time: SQLite has no tuple IN, and there are only two kinds to ask about. */
    @Query("$ASSET_STATE_QUERY WHERE k.assetKind = :assetKind AND k.derivationIndex IN (:derivationIndices)")
    abstract suspend fun getAssetStates(
        assetKind: CoinageEntryLocal.AssetKind,
        derivationIndices: List<Int>,
    ): List<CoinageAssetStateProjection>
}

/** An entry with its assets, fetched in one query rather than three. */
class CoinageEntryWithAssets(
    @Embedded val entry: CoinageEntryLocal,
    @Relation(parentColumn = "id", entityColumn = "entryId")
    val inputs: List<CoinageEntryInputLocal>,
    @Relation(parentColumn = "id", entityColumn = "entryId")
    val outputs: List<CoinageEntryOutputLocal>,
)

class CoinageAssetStateProjection(
    val assetKind: CoinageEntryLocal.AssetKind,
    val derivationIndex: Int,
    val minterStatus: CoinageEntryLocal.Status?,
    val handedOff: Boolean,
    /** Of the at-most-one non-failed consumer — the Unique consumer invariant is what makes LIMIT 1 sound. */
    val consumerStatus: CoinageEntryLocal.Status?,
)
