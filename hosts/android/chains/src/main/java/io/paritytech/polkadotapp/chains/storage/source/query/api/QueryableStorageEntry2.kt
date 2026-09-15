package io.paritytech.polkadotapp.chains.storage.source.query.api

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decode
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.encode
import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.metadata.module.StorageEntry
import io.novasama.substrate_sdk_android.runtime.metadata.storageKey
import io.paritytech.polkadotapp.chains.storage.source.query.StorageKeyComponents
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.WithRawValue
import kotlinx.coroutines.flow.Flow
import kotlin.reflect.KType

typealias QueryableStorageBinder2<K1, K2, V> = (dynamicInstance: Any, key1: K1, key2: K2) -> V

interface QueryableStorageEntry2<I1, I2, T> {
    context(storage: StorageQueryContext)
    fun observe(
        argument1: I1,
        argument2: I2,
    ): Flow<T?>

    context(storage: StorageQueryContext)
    suspend fun keys(): List<Pair<I1, I2>>

    context(storage: StorageQueryContext)
    suspend fun keys(argument1: I1): List<Pair<I1, I2>>

    context(storage: StorageQueryContext)
    suspend fun entries(keys: List<Pair<I1, I2>>): Map<Pair<I1, I2>, T>

    context(storage: StorageQueryContext)
    suspend fun entries(argument1: I1): Map<Pair<I1, I2>, T>

    context(storage: StorageQueryContext)
    suspend fun query(argument1: I1, argument2: I2): T?

    context(storage: StorageQueryContext)
    suspend fun findExistingKeys(keys: List<Pair<I1, I2>>): Set<Pair<I1, I2>>

    context(storage: StorageQueryContext)
    fun observeWithRaw(argument1: I1, argument2: I2): Flow<WithRawValue<T?>>

    context(storage: StorageQueryContext)
    suspend fun observe(arguments: List<Pair<I1, I2>>): Flow<Map<Pair<I1, I2>, T?>>

    fun storageKey(argument1: I1, argument2: I2): String
}

context(storage: StorageQueryContext)
suspend fun <I1, I2, T : Any> QueryableStorageEntry2<I1, I2, T>.queryNonNull(argument1: I1, argument2: I2): T = requireNotNull(query(argument1, argument2))

class RealQueryableStorageEntry2<I1, I2, T>(
    private val runtimeSnapshot: RuntimeSnapshot,
    private val storageEntry: StorageEntry,
    private val encoders: Entry2Encoders<I1, I2, T>
) : QueryableStorageEntry2<I1, I2, T> {
    override fun storageKey(argument1: I1, argument2: I2): String {
        val encoded = encoders.encodeKeys(argument1, argument2)
        return storageEntry.storageKey(runtimeSnapshot, *encoded.toTypedArray())
    }

    context(storage: StorageQueryContext)
    override fun observe(
        argument1: I1,
        argument2: I2,
    ): Flow<T?> {
        return with(storage) {
            storageEntry.observe(
                keyArguments = encoders.encodeKeys(argument1, argument2).toTypedArray(),
                binding = { decoded -> decoded?.let { encoders.decodeValue(it, argument1, argument2) } }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun observe(arguments: List<Pair<I1, I2>>): Flow<Map<Pair<I1, I2>, T?>> {
        return with(storage) {
            storageEntry.observe(
                keysArguments = arguments.map { encoders.encodeKeys(it.first, it.second) },
                keyExtractor = ::bindFullKey,
                binding = { decoded, key -> decoded?.let { encoders.decodeValue(it, key.first, key.second) } as T }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun keys(): List<Pair<I1, I2>> {
        return with(storage) {
            storageEntry.keys().map(::bindFullKey)
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun keys(argument1: I1): List<Pair<I1, I2>> {
        return with(storage) {
            storageEntry.keys(encoders.encodeKey1(argument1)).map(::bindFullKey)
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun entries(argument1: I1): Map<Pair<I1, I2>, T> {
        return with(storage) {
            storageEntry.entries(
                encoders.encodeKey1(argument1),
                keyExtractor = ::bindFullKey,
                binding = { decoded, key -> decoded?.let { encoders.decodeValue(it, key.first, key.second) } as T }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun findExistingKeys(keys: List<Pair<I1, I2>>): Set<Pair<I1, I2>> {
        return with(storage) {
            storageEntry.findExistingKeys(
                keysArguments = keys.map { (key1, key2) -> encoders.encodeKeys(key1, key2) },
                keyExtractor = ::bindFullKey
            )
        }
    }

    context(storage: StorageQueryContext)
    override fun observeWithRaw(argument1: I1, argument2: I2): Flow<WithRawValue<T?>> {
        return with(storage) {
            storageEntry.observeWithRaw(
                keyArguments = encoders.encodeKeys(argument1, argument2).toTypedArray(),
                binding = { decoded -> decoded?.let { encoders.decodeValue(it, argument1, argument2) } }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun query(argument1: I1, argument2: I2): T? {
        return with(storage) {
            storageEntry.query(
                keyArguments = encoders.encodeKeys(argument1, argument2).toTypedArray(),
                binding = { decoded -> decoded?.let { encoders.decodeValue(it, argument1, argument2) } }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun entries(keys: List<Pair<I1, I2>>): Map<Pair<I1, I2>, T> {
        return with(storage) {
            storageEntry.entries(
                keysArguments = keys.map { encoders.encodeKeys(it.first, it.second) },
                keyExtractor = ::bindFullKey,
                binding = { decoded, key -> decoded?.let { encoders.decodeValue(it, key.first, key.second) } as T }
            )
        }
    }

    private fun bindFullKey(storageKeyComponents: StorageKeyComponents): Pair<I1, I2> {
        val (first: Any?, second: Any?) = storageKeyComponents

        return encoders.decodeKey(first, second)
    }
}

sealed interface Entry2Encoders<I1, I2, T> {
    fun decodeValue(instance: Any, key1: I1, key2: I2): T

    fun decodeKey(instance1: Any?, instance2: Any?): Pair<I1, I2>

    fun encodeKeys(key1: I1, key2: I2): List<Any?>

    fun encodeKey1(key1: I1): Any?

    class Auto<I1, I2, T>(
        private val key1Type: KType,
        private val key2Type: KType,
        private val valueType: KType
    ) : Entry2Encoders<I1, I2, T> {
        override fun decodeValue(instance: Any, key1: I1, key2: I2): T {
            return Scale.decode(valueType, instance)
        }

        override fun decodeKey(instance1: Any?, instance2: Any?): Pair<I1, I2> {
            return Pair(
                first = Scale.decode(key1Type, instance1),
                second = Scale.decode(key2Type, instance2),
            )
        }

        override fun encodeKeys(key1: I1, key2: I2): List<Any?> {
            return listOf(
                Scale.encode(key1Type, key1),
                Scale.encode(key2Type, key2)
            )
        }

        override fun encodeKey1(key1: I1): Any? {
            return Scale.encode(key1Type, key1)
        }
    }

    class Manual<I1, I2, T>(
        private val binding: QueryableStorageBinder2<I1, I2, T>,
        toKey1Binding: QueryableStorageToKeyBinder<I1>?,
        toKey2Binding: QueryableStorageToKeyBinder<I2>?,
        fromKey1Binding: QueryableStorageFromKeyBinder<I1>?,
        fromKey2Binding: QueryableStorageFromKeyBinder<I2>?
    ) : Entry2Encoders<I1, I2, T> {
        @Suppress("UNCHECKED_CAST")
        private val toKey1BindingOrDefault = toKey1Binding ?: { it as I1 }

        @Suppress("UNCHECKED_CAST")
        private val toKey2BindingOrDefault = toKey2Binding ?: { it as I2 }

        private val fromKey1BindingOrDefault = fromKey1Binding ?: { it }
        private val fromKey2BindingOrDefault = fromKey2Binding ?: { it }

        override fun decodeValue(instance: Any, key1: I1, key2: I2): T {
            return binding(instance, key1, key2)
        }

        override fun decodeKey(instance1: Any?, instance2: Any?): Pair<I1, I2> {
            return Pair(
                toKey1BindingOrDefault(instance1),
                toKey2BindingOrDefault(instance2)
            )
        }

        override fun encodeKeys(key1: I1, key2: I2): List<Any?> {
            return listOf(
                fromKey1BindingOrDefault(key1),
                fromKey2BindingOrDefault(key2)
            )
        }

        override fun encodeKey1(key1: I1): Any? {
            return fromKey1BindingOrDefault(key1)
        }
    }
}
