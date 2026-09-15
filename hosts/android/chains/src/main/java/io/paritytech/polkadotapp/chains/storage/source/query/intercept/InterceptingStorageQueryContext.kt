package io.paritytech.polkadotapp.chains.storage.source.query.intercept

import io.novasama.substrate_sdk_android.runtime.metadata.module.StorageEntry
import io.paritytech.polkadotapp.chains.storage.source.query.DynamicInstanceBinder
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.WithRawValue
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Decorates a [StorageQueryContext], delegating every member except the single-key value producers
 * (`observe` / `observeWithRaw` / `query`). Those route their decoded value through any interceptors registered
 * for the entry's `(module, storage)`; a non-targeted read pays only one registry lookup. Map-returning reads
 * (`observeByPrefix` / `entries` / multi-key `observe`) stay delegated — the videogame override only needs the
 * single-key paths.
 */
internal class InterceptingStorageQueryContext(
    private val delegate: StorageQueryContext,
    private val registry: StorageInterceptorRegistry,
) : StorageQueryContext by delegate {
    override fun <V> StorageEntry.observe(vararg keyArguments: Any?, binding: DynamicInstanceBinder<V>): Flow<V> {
        val entry = this
        return entry.intercepted(keyArguments, raw = { with(delegate) { entry.observe(*keyArguments, binding = binding) } }) { interceptors, storageKey, downstream ->
            foldObserve(interceptors, entry, storageKey, downstream)
        }
    }

    override fun <V> StorageEntry.observeWithRaw(vararg keyArguments: Any?, binding: DynamicInstanceBinder<V>): Flow<WithRawValue<V>> {
        val entry = this
        return entry.intercepted(keyArguments, raw = { with(delegate) { entry.observeWithRaw(*keyArguments, binding = binding) } }) { interceptors, storageKey, downstream ->
            downstream.map { raw ->
                WithRawValue(at = raw.at, raw = raw.raw, chainId = raw.chainId, value = foldQuery(interceptors, entry, storageKey, keyArguments, raw.value))
            }
        }
    }

    override suspend fun <V> StorageEntry.query(vararg keyArguments: Any?, binding: DynamicInstanceBinder<V>): V {
        val entry = this
        val raw = with(delegate) { entry.query(*keyArguments, binding = binding) }

        val interceptors = registry.forTarget(entry.moduleName, entry.name)
        if (interceptors.isEmpty()) return raw

        return foldQuery(interceptors, entry, entry.storageKey(keyArguments), keyArguments, raw)
    }

    // Shared dispatch for the value-producing reads: a registry miss returns the raw value/flow untouched
    // (one map lookup), a hit hands the matching interceptors and the storage key to [transform].
    private inline fun <R> StorageEntry.intercepted(
        keyArguments: Array<out Any?>,
        raw: () -> R,
        transform: (interceptors: List<StorageQueryInterceptor>, storageKey: String, raw: R) -> R,
    ): R {
        val interceptors = registry.forTarget(moduleName, name)
        val rawValue = raw()
        if (interceptors.isEmpty()) return rawValue

        return transform(interceptors, storageKey(keyArguments), rawValue)
    }

    private fun StorageEntry.storageKey(keyArguments: Array<out Any?>): String =
        with(delegate) { createStorageKey(*keyArguments) }

    private fun <V> foldObserve(
        interceptors: List<StorageQueryInterceptor>,
        entry: StorageEntry,
        storageKey: String,
        downstream: Flow<V>,
    ): Flow<V> = interceptors.fold(downstream) { acc, interceptor ->
        interceptor.interceptObserve(StorageObserveRequest(entry.moduleName, entry.name, storageKey, acc))
    }

    private suspend fun <V> foldQuery(
        interceptors: List<StorageQueryInterceptor>,
        entry: StorageEntry,
        storageKey: String,
        keyArguments: Array<out Any?>,
        value: V,
    ): V = interceptors.fold(value) { acc, interceptor ->
        interceptor.interceptQuery(StorageQueryRequest(entry.moduleName, entry.name, storageKey, keyArguments.toList(), acc))
    }
}
