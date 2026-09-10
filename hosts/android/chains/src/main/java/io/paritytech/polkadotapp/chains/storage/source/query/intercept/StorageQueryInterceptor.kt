package io.paritytech.polkadotapp.chains.storage.source.query.intercept

import kotlinx.coroutines.flow.Flow

/** The `(module, storage)` pair an interceptor handles. Used as the registry's dispatch key. */
data class StorageTarget(val module: String, val storage: String)

/**
 * A one-shot read of a single storage entry. The [value] is already decoded (the binding ran); [keyArguments]
 * are the encoded key components and [storageKey] the full hex key, so an interceptor scopes by key string.
 */
class StorageQueryRequest<T>(
    val module: String,
    val storage: String,
    val storageKey: String,
    val keyArguments: List<Any?>,
    val value: T,
)

/** Subscription form of [StorageQueryRequest]: carries the [downstream] decoded-value flow instead of a value. */
class StorageObserveRequest<T>(
    val module: String,
    val storage: String,
    val storageKey: String,
    val downstream: Flow<T>,
)

/** Typed view of the decoded value. Dispatch by [StorageTarget] already guarantees the entry, so the cast is safe. */
@Suppress("UNCHECKED_CAST")
inline fun <reified V> StorageQueryRequest<*>.valueAs(): V = value as V

/**
 * Post-decoding hook on the storage read path. An interceptor declares the [targets] it handles and may rewrite
 * the decoded value for those entries; both entry points default to pass-through. Dispatch is target-indexed, so
 * a read of a non-targeted entry never reaches an interceptor. Contributed via `@IntoSet`; collected by
 * [StorageInterceptorRegistry].
 */
interface StorageQueryInterceptor {
    val targets: Set<StorageTarget>

    suspend fun <T> interceptQuery(request: StorageQueryRequest<T>): T = request.value

    fun <T> interceptObserve(request: StorageObserveRequest<T>): Flow<T> = request.downstream
}
