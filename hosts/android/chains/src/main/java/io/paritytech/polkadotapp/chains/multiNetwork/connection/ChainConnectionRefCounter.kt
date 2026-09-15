package io.paritytech.polkadotapp.chains.multiNetwork.connection

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

interface ChainConnectionRefCounter {
    fun shouldConnectionBeEnabled(chainId: ChainId): Flow<Boolean>

    suspend fun requestConnectionEnabled(chainIds: Set<ChainId>, label: String): EnabledChainConnectionReference
}

suspend fun ChainConnectionRefCounter.requestConnectionEnabled(chainId: ChainId, label: String): EnabledChainConnectionReference {
    return requestConnectionEnabled(setOf(chainId), label)
}

suspend fun <R> ChainConnectionRefCounter.withConnectionEnabled(
    chainIds: Set<ChainId>,
    label: String,
    block: suspend () -> R
): R {
    val ref = requestConnectionEnabled(chainIds, label)
    return try {
        block()
    } finally {
        ref.release()
    }
}

suspend fun <R> ChainConnectionRefCounter.withConnectionEnabled(
    chainId: ChainId,
    label: String,
    block: suspend () -> R
): R {
    return withConnectionEnabled(setOf(chainId), label, block)
}

interface EnabledChainConnectionReference {
    suspend fun release()
}

@Singleton
class RealChainConnectionRefCounter @Inject constructor() : ChainConnectionRefCounter {
    private val mutex = Mutex()
    private val refCounts = mutableMapOf<ChainId, MutableStateFlow<Int>>()

    override fun shouldConnectionBeEnabled(chainId: ChainId): Flow<Boolean> {
        return getOrCreateRefCountFlow(chainId)
            .map { it > 0 }
            .distinctUntilChanged()
    }

    override suspend fun requestConnectionEnabled(
        chainIds: Set<ChainId>,
        label: String
    ): EnabledChainConnectionReference {
        mutex.withLock {
            chainIds.forEach { chainId ->
                val flow = getOrCreateRefCountFlow(chainId)
                val newCount = flow.value + 1
                flow.value = newCount
                Timber.d("Requested connection for $chainId by '$label', refCount=$newCount")
            }
        }

        return RealEnabledChainConnectionReference(chainIds, label)
    }

    private fun getOrCreateRefCountFlow(chainId: ChainId): MutableStateFlow<Int> {
        return refCounts.getOrPut(chainId) { MutableStateFlow(0) }
    }

    private inner class RealEnabledChainConnectionReference(
        private val chainIds: Set<ChainId>,
        private val label: String
    ) : EnabledChainConnectionReference {
        private var released = false

        override suspend fun release() {
            withContext(NonCancellable) {
                mutex.withLock {
                    check(!released) { "Reference '$label' for chains $chainIds has already been released" }
                    released = true

                    chainIds.forEach { chainId ->
                        val flow = refCounts[chainId] ?: return@forEach
                        val newCount = (flow.value - 1).coerceAtLeast(0)
                        flow.value = newCount
                        Timber.d("Released connection for $chainId by '$label', refCount=$newCount")
                    }
                }
            }
        }
    }
}
