package io.paritytech.polkadotapp.chains.storage.source.query.api

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decode
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.encode
import io.novasama.substrate_sdk_android.runtime.metadata.module.StorageEntry
import io.paritytech.polkadotapp.chains.storage.source.query.StorageKeyComponents
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.WithRawValue
import kotlinx.coroutines.flow.Flow
import kotlin.reflect.KType

interface QueryableStorageEntry3<I1, I2, I3, T> {
    context(storage: StorageQueryContext)
    suspend fun query(key1: I1, key2: I2, key3: I3): T?

    context(storage: StorageQueryContext)
    fun observeWithRaw(key1: I1, key2: I2, key3: I3): Flow<WithRawValue<T?>>

    context(storage: StorageQueryContext)
    suspend fun entries(key1: I1, key2: I2): Map<Triple<I1, I2, I3>, T?>

    context(storage: StorageQueryContext)
    suspend fun entries(keys: List<Triple<I1, I2, I3>>): Map<Triple<I1, I2, I3>, T?>

    context(storage: StorageQueryContext)
    suspend fun findExistingKeys(keys: Collection<Triple<I1, I2, I3>>): Set<Triple<I1, I2, I3>>

    context(storage: StorageQueryContext)
    suspend fun keyExists(argument1: I1, argument2: I2, argument3: I3): Boolean
}

context(storage: StorageQueryContext)
suspend fun <I1, I2, I3, T : Any> QueryableStorageEntry3<I1, I2, I3, T>.queryNonNull(key1: I1, key2: I2, key3: I3): T = with(storage) { requireNotNull(query(key1, key2, key3)) }

class RealQueryableStorageEntry3<I1, I2, I3, T>(
    private val storageEntry: StorageEntry,
    private val key1Type: KType,
    private val key2Type: KType,
    private val key3Type: KType,
    private val valueType: KType
) : QueryableStorageEntry3<I1, I2, I3, T> {
    context(storage: StorageQueryContext)
    override suspend fun query(key1: I1, key2: I2, key3: I3): T? {
        return with(storage) {
            storageEntry.query(
                Scale.encode(key1Type, key1),
                Scale.encode(key2Type, key2),
                Scale.encode(key3Type, key3),
                binding = { decoded -> decoded?.let { Scale.decode(valueType, it) } }
            )
        }
    }

    context(storage: StorageQueryContext)
    override fun observeWithRaw(key1: I1, key2: I2, key3: I3): Flow<WithRawValue<T?>> {
        return with(storage) {
            storageEntry.observeWithRaw(
                Scale.encode(key1Type, key1),
                Scale.encode(key2Type, key2),
                Scale.encode(key3Type, key3),
                binding = { decoded -> decoded?.let { Scale.decode(valueType, it) } }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun entries(key1: I1, key2: I2): Map<Triple<I1, I2, I3>, T?> {
        return with(storage) {
            storageEntry.entries(
                Scale.encode(key1Type, key1),
                Scale.encode(key2Type, key2),
                keyExtractor = { it.bindKeys() },
                binding = { decoded, _ -> decoded?.let { Scale.decode(valueType, it) } },
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun entries(keys: List<Triple<I1, I2, I3>>): Map<Triple<I1, I2, I3>, T?> {
        return with(storage) {
            storageEntry.entries(
                keysArguments = keys.encoded(),
                keyExtractor = { it.bindKeys() },
                binding = { decoded, _ -> decoded?.let { Scale.decode(valueType, it) } },
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun findExistingKeys(keys: Collection<Triple<I1, I2, I3>>): Set<Triple<I1, I2, I3>> {
        return with(storage) {
            storageEntry.findExistingKeys(
                keysArguments = keys.encoded(),
                keyExtractor = { it.bindKeys() }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun keyExists(argument1: I1, argument2: I2, argument3: I3): Boolean {
        val key = Triple(argument1, argument2, argument3)
        val existingKeys = with(storage) { findExistingKeys(listOf(key)) }

        return existingKeys.contains(key)
    }

    private fun StorageKeyComponents.bindKeys(): Triple<I1, I2, I3> {
        val (key1, key2, key3) = values

        return Triple(
            Scale.decode(key1Type, key1),
            Scale.decode(key2Type, key2),
            Scale.decode(key3Type, key3),
        )
    }

    private fun Collection<Triple<I1, I2, I3>>.encoded() = map {
        listOf(
            Scale.encode(key1Type, it.first),
            Scale.encode(key2Type, it.second),
            Scale.encode(key3Type, it.third)
        )
    }
}
