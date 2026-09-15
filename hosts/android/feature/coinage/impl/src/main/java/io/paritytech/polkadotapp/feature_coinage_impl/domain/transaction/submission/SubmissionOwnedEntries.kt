package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.submission

import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogI
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.coinageLogId
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Which entries submission tracking currently owns, so the recovery pass skips exactly those and each entry
 * has one writer at a time.
 *
 * Registration acquires inside its own database transaction, so a committed row always has an owner and a
 * pass can never evaluate an entry the tracker is about to write. The pass asks per entry at the moment it
 * reaches that entry rather than taking a copy up front — a copy would not contain an entry registered while
 * the pass was already running, and the pass would then evaluate it underneath its watcher.
 *
 * Deliberately volatile. A crash takes the set with it, and an empty set after restart is the correct answer
 * rather than stale state to reconcile: a durable set would strand entries behind a watcher that no longer
 * exists. This is sound only because the client runs in one OS process — if WorkManager is ever configured
 * with `android:process`, this stops being an exclusivity mechanism.
 *
 * Ownership is one-shot: released exactly once and never re-acquired, not even across a resubmission.
 */
@Singleton
class SubmissionOwnedEntries @Inject constructor() {
    private val mutex = Mutex()
    private val owned = mutableSetOf<Long>()
    private val everReleased = mutableSetOf<Long>()

    suspend fun acquire(id: CoinageTransactionId) = mutex.withLock {
        if (id.value !in everReleased) {
            owned += id.value
            coinageLogD("${coinageLogId(id)} submission-ownership acquired")
        } else {
            coinageLogW("${coinageLogId(id)} submission-ownership acquire-ignored reason=already-released")
        }
    }

    suspend fun release(id: CoinageTransactionId) = mutex.withLock {
        owned -= id.value
        everReleased += id.value

        coinageLogI("${coinageLogId(id)} submission-ownership released")
    }

    suspend fun isOwnedBySubmission(id: CoinageTransactionId): Boolean = mutex.withLock {
        id.value in owned
    }
}
