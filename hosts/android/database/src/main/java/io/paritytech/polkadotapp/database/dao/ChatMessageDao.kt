package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import io.paritytech.polkadotapp.database.model.ChatMessageLocal
import io.paritytech.polkadotapp.database.model.ChatMessagePendingExpansionLocal
import io.paritytech.polkadotapp.database.model.ChatMessageSearchRow
import io.paritytech.polkadotapp.database.model.TransferRetryStateLocal
import kotlinx.coroutines.flow.Flow

@Dao
abstract class ChatMessageDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insert(local: List<ChatMessageLocal>)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    protected abstract suspend fun insertIfNotExists(local: List<ChatMessageLocal>): List<Long>

    /**
     * [onSaved] runs inside the same transaction as the insert, so a caller can make a fact durable exactly
     * when the message is — neither can be rolled back without the other.
     */
    @Transaction
    open suspend fun saveMessage(local: ChatMessageLocal, onSaved: suspend () -> Unit) {
        saveMessages(listOf(local))
        onSaved()
    }

    @Transaction
    open suspend fun saveMessageIfNotExists(local: ChatMessageLocal): Long {
        return saveMessagesIfNotExist(listOf(local)).single()
    }

    @Transaction
    open suspend fun saveMessages(locals: List<ChatMessageLocal>) {
        insert(locals)
        insertPendingExpansions(locals.pendingExpansions())
    }

    @Transaction
    open suspend fun saveMessagesIfNotExist(locals: List<ChatMessageLocal>): List<Long> {
        val rowIds = insertIfNotExists(locals)
        val inserted = locals.filterIndexed { index, _ -> rowIds[index] >= 0 }
        insertPendingExpansions(inserted.pendingExpansions())
        return rowIds
    }

    private fun List<ChatMessageLocal>.pendingExpansions(): List<ChatMessagePendingExpansionLocal> {
        return filter { it.type == ChatMessageLocal.Type.COMPACTION_COMMIT && it.origin.type != ChatMessageLocal.OriginType.USER }
            .map { ChatMessagePendingExpansionLocal(commitId = it.id, retryState = TransferRetryStateLocal.None) }
    }

    @Query("SELECT * FROM chat_messages WHERE chatId = :chatId ORDER BY timestamp DESC")
    abstract fun subscribeMessages(chatId: ByteArray): Flow<List<ChatMessageLocal>>

    @Query("SELECT * FROM chat_messages WHERE chatId = :chatId ORDER BY timestamp ASC")
    abstract suspend fun getMessages(chatId: ByteArray): List<ChatMessageLocal>

    @Query("SELECT * FROM chat_messages WHERE updatedAt > :after ORDER BY updatedAt ASC")
    abstract suspend fun getMessagesUpdatedAfter(after: Long): List<ChatMessageLocal>

    @Query("SELECT * FROM chat_messages WHERE id = :messageId")
    abstract suspend fun getMessage(messageId: String): ChatMessageLocal?

    @Query("SELECT * FROM chat_messages WHERE chatId = :chatId AND status = :status AND origintype == 'USER'")
    abstract fun subscribeOutgoingMessagesByStatus(
        chatId: ByteArray,
        status: ChatMessageLocal.Status
    ): Flow<List<ChatMessageLocal>>

    @Query("""
        SELECT * FROM chat_messages
        WHERE chatId = :chatId AND type = :type
        AND status = :status
        AND ((:isOutgoing = 1 AND origintype = 'USER') OR (:isOutgoing = 0 AND origintype != 'USER'))
    """)
    abstract fun subscribeMessages(chatId: ByteArray, type: ChatMessageLocal.Type, status: ChatMessageLocal.Status, isOutgoing: Boolean): Flow<List<ChatMessageLocal>>

    @Query("SELECT * FROM chat_messages WHERE id = :messageId")
    abstract fun subscribeMessageById(messageId: String): Flow<ChatMessageLocal?>

    @Query("SELECT * FROM chat_messages WHERE type IN (:types)")
    abstract fun subscribeMessagesByTypes(types: List<ChatMessageLocal.Type>): Flow<List<ChatMessageLocal>>

    @Query("""
        SELECT id, chatId, timestamp, searchableContent FROM chat_messages
        WHERE isInternal = 0
            AND chatId IN (:chatIds)
            AND searchableContent LIKE '%' || :query || '%' ESCAPE '\'
        ORDER BY timestamp DESC
        LIMIT :limit
    """)
    abstract suspend fun searchMessages(
        query: String,
        chatIds: List<ByteArray>,
        limit: Int
    ): List<ChatMessageSearchRow>

    @Query("UPDATE chat_messages SET status = :newStatus, updatedAt = :updatedAt WHERE id = :messageId")
    abstract suspend fun updateStatus(messageId: String, newStatus: ChatMessageLocal.Status, updatedAt: Long): Int

    @Update(entity = ChatMessageLocal::class)
    abstract suspend fun updateMessagesContents(updates: List<MessageContentUpdateLocal>)

    @Query("UPDATE chat_messages SET status = :newStatus, updatedAt = :updatedAt WHERE id IN (:messageIds)")
    abstract suspend fun updateMessagesStatus(messageIds: List<String>, newStatus: ChatMessageLocal.Status, updatedAt: Long): Int

    @Query(
        """
        UPDATE chat_messages SET status = :toStatus
        WHERE chatId = :chatId AND status = :fromStatus AND origintype == 'USER'
        AND NOT EXISTS (SELECT 1 FROM chat_message_compaction_links WHERE originalId = chat_messages.id)
        """
    )
    abstract suspend fun updateOutgoingMessagesStatusForChat(chatId: ByteArray, fromStatus: ChatMessageLocal.Status, toStatus: ChatMessageLocal.Status)

    @Query(
        """
        UPDATE chat_messages SET status = :toStatus
        WHERE chatId = :chatId AND status = :fromStatus AND origintype == 'USER' AND type IN (:types)
        AND NOT EXISTS (SELECT 1 FROM chat_message_compaction_links WHERE originalId = chat_messages.id)
        """
    )
    abstract suspend fun updateOutgoingMessagesStatusForChatWithTypes(chatId: ByteArray, fromStatus: ChatMessageLocal.Status, toStatus: ChatMessageLocal.Status, types: List<ChatMessageLocal.Type>)

    @Query(
        """
        UPDATE chat_messages SET status = :toStatus
        WHERE chatId = :chatId AND status = :fromStatus AND origintype == 'USER' AND type NOT IN (:types)
        AND NOT EXISTS (SELECT 1 FROM chat_message_compaction_links WHERE originalId = chat_messages.id)
        """
    )
    abstract suspend fun updateOutgoingMessagesStatusForChatExcludingTypes(chatId: ByteArray, fromStatus: ChatMessageLocal.Status, toStatus: ChatMessageLocal.Status, types: List<ChatMessageLocal.Type>)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    protected abstract suspend fun insertPendingExpansions(pending: List<ChatMessagePendingExpansionLocal>)

    @Query("DELETE FROM chat_messages WHERE id IN (:messageIds)")
    protected abstract suspend fun removeMessageRows(messageIds: List<String>)

    @Query("DELETE FROM chat_message_compaction_links WHERE originalId IN (:originalIds)")
    protected abstract suspend fun deleteCompactionLinksOf(originalIds: List<String>)

    @Query("DELETE FROM chat_message_pending_expansions WHERE commitId = :commitId")
    protected abstract suspend fun clearPendingExpansion(commitId: String)

    @Transaction
    open suspend fun remove(messageId: String) {
        removeMessageRows(listOf(messageId))
        deleteCompactionLinksOf(listOf(messageId))
        clearPendingExpansion(messageId)
    }

    @Query("UPDATE chat_messages SET status = 'IS_READ' WHERE chatId = :chatId AND timestamp <= :timestamp AND status = 'NEW' AND origintype != 'USER'")
    abstract suspend fun markMessagesAsReadUpToTimestamp(chatId: ByteArray, timestamp: Long)

    @Query("UPDATE chat_messages SET status = 'IS_READ' WHERE chatId = :chatId AND status = 'NEW' AND origintype != 'USER' AND type IN (:types)")
    abstract suspend fun markMessagesByTypesAsRead(chatId: ByteArray, types: List<String>)

    @Query("UPDATE chat_messages SET status = 'IS_READ' WHERE id = :messageId")
    abstract suspend fun markMessageAsRead(messageId: String)

    @Query("SELECT * FROM chat_messages WHERE chatId = :chatId AND type = 'UNSUPPORTED'")
    abstract suspend fun getUnsupportedMessages(chatId: ByteArray): List<ChatMessageLocal>

    @Query("DELETE FROM chat_messages WHERE chatId = :chatId")
    abstract suspend fun deleteAllMessageRows(chatId: ByteArray)

    @Query("DELETE FROM chat_message_compaction_links WHERE originalId IN (SELECT id FROM chat_messages WHERE chatId = :chatId)")
    abstract suspend fun deleteCompactionLinksForChat(chatId: ByteArray)

    @Query("DELETE FROM chat_message_pending_expansions WHERE commitId IN (SELECT id FROM chat_messages WHERE chatId = :chatId)")
    abstract suspend fun deletePendingExpansionsForChat(chatId: ByteArray)

    @Transaction
    open suspend fun deleteAllMessages(chatId: ByteArray) {
        deleteCompactionLinksForChat(chatId)
        deletePendingExpansionsForChat(chatId)
        deleteAllMessageRows(chatId)
    }

    @Query("SELECT MAX(timestamp) FROM chat_messages WHERE chatId = :chatId")
    abstract suspend fun getLatestTimestamp(chatId: ByteArray): Long?

    @Query("UPDATE chat_messages SET timestamp = timestamp + :delta WHERE chatId = :chatId")
    abstract suspend fun shiftTimestamps(chatId: ByteArray, delta: Long)

    @Transaction
    open suspend fun updateTimestamps(chatId: ByteArray, targetTimestamp: Long) {
        val latest = getLatestTimestamp(chatId) ?: return
        val delta = targetTimestamp - latest
        if (delta != 0L) {
            shiftTimestamps(chatId, delta)
        }
    }

    @Query("SELECT id, status FROM chat_messages WHERE id IN (:messageIds)")
    abstract suspend fun getMessageStatuses(messageIds: List<String>): List<MessageStatusProjection>

    data class MessageStatusProjection(
        val id: String,
        val status: ChatMessageLocal.Status
    )

    class MessageContentUpdateLocal(
        val id: String,
        val content: ByteArray?,
        val type: ChatMessageLocal.Type,
        val updatedAt: Long
    )
}
