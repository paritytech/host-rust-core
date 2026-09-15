package io.paritytech.polkadotapp.chains.storage.source.query.api

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decode
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.encode
import io.novasama.substrate_sdk_android.runtime.metadata.module.StorageEntry
import io.paritytech.polkadotapp.chains.storage.source.query.StorageKeyComponents
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import kotlin.reflect.KType

data class StorageKey4<I1, I2, I3, I4>(
    val first: I1,
    val second: I2,
    val third: I3,
    val fourth: I4
)

interface QueryableStorageEntry4<I1, I2, I3, I4, T> {
    context(storage: StorageQueryContext)
    suspend fun query(key1: I1, key2: I2, key3: I3, key4: I4): T?

    context(storage: StorageQueryContext)
    suspend fun entries(keys: List<StorageKey4<I1, I2, I3, I4>>): Map<StorageKey4<I1, I2, I3, I4>, T?>

    context(storage: StorageQueryContext)
    suspend fun findExistingKeys(keys: Collection<StorageKey4<I1, I2, I3, I4>>): Set<StorageKey4<I1, I2, I3, I4>>
}

class RealQueryableStorageEntry4<I1, I2, I3, I4, T>(
    private val storageEntry: StorageEntry,
    private val key1Type: KType,
    private val key2Type: KType,
    private val key3Type: KType,
    private val key4Type: KType,
    private val valueType: KType
) : QueryableStorageEntry4<I1, I2, I3, I4, T> {
    context(storage: StorageQueryContext)
    override suspend fun query(key1: I1, key2: I2, key3: I3, key4: I4): T? {
        return with(storage) {
            storageEntry.query(
                Scale.encode(key1Type, key1),
                Scale.encode(key2Type, key2),
                Scale.encode(key3Type, key3),
                Scale.encode(key4Type, key4),
                binding = { decoded -> decoded?.let { Scale.decode(valueType, it) } }
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun entries(keys: List<StorageKey4<I1, I2, I3, I4>>): Map<StorageKey4<I1, I2, I3, I4>, T?> {
        return with(storage) {
            storageEntry.entries(
                keysArguments = keys.encoded(),
                keyExtractor = { it.bindKeys() },
                binding = { decoded, _ -> decoded?.let { Scale.decode(valueType, it) } },
            )
        }
    }

    context(storage: StorageQueryContext)
    override suspend fun findExistingKeys(keys: Collection<StorageKey4<I1, I2, I3, I4>>): Set<StorageKey4<I1, I2, I3, I4>> {
        return with(storage) {
            storageEntry.findExistingKeys(
                keysArguments = keys.encoded(),
                keyExtractor = { it.bindKeys() }
            )
        }
    }

    private fun StorageKeyComponents.bindKeys(): StorageKey4<I1, I2, I3, I4> {
        val (key1, key2, key3, key4) = values

        return StorageKey4(
            Scale.decode(key1Type, key1),
            Scale.decode(key2Type, key2),
            Scale.decode(key3Type, key3),
            Scale.decode(key4Type, key4),
        )
    }

    private fun Collection<StorageKey4<I1, I2, I3, I4>>.encoded() = map {
        listOf(
            Scale.encode(key1Type, it.first),
            Scale.encode(key2Type, it.second),
            Scale.encode(key3Type, it.third),
            Scale.encode(key4Type, it.fourth)
        )
    }
}
