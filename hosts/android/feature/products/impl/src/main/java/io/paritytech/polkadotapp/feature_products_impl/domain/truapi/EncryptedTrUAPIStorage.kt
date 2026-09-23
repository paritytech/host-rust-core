package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.parity.truapi.HostCoreStorage
import io.parity.truapi.HostStorage
import io.paritytech.polkadotapp.common.data.storage.preferences.encrypted.EncryptedPreferences
import uniffi.truapi.HostLocalStorageReadError
import uniffi.truapi_server.HostRejection
import uniffi.truapi_server.HostStorageException

/**
 * Product-scoped storage for the Rust core, encrypted at rest.
 *
 * [namespace] carries the product id, matching how the native host namespaces
 * `localStorageRead`/`Write`/`Clear`: one product must not be able to read
 * another's keys.
 */
class EncryptedHostStorage(
    private val preferences: EncryptedPreferences,
    private val namespace: String,
) : HostStorage {
    override fun read(key: String): ByteArray? = readValue(preferences, qualify(key))

    override fun write(key: String, value: ByteArray) {
        writeValue(preferences, qualify(key), value)
            ?.let { throw storageFailure("product storage: $it") }
    }

    override fun clear(key: String) {
        runCatching { preferences.removeKey(qualify(key)) }
            .getOrElse { throw storageFailure("failed to clear product storage key: ${it.message}") }
    }

    private fun qualify(key: String) = "$namespace/$key"
}

/**
 * Core-owned storage: auth session, pairing identity, and persisted permission
 * decisions.
 *
 * Deliberately *not* product-scoped. The pairing identity belongs to the user,
 * not to a product, and scoping it per product would make every product demand
 * its own pairing. The core disambiguates internally through the SCALE-encoded
 * `CoreStorageKey` it passes here.
 */
class EncryptedHostCoreStorage(
    private val preferences: EncryptedPreferences,
) : HostCoreStorage {
    override fun read(key: ByteArray): ByteArray? = readValue(preferences, qualify(key))

    override fun write(key: ByteArray, value: ByteArray) {
        writeValue(preferences, qualify(key), value)
            ?.let { throw HostRejection.Rejected("core storage: $it") }
    }

    override fun clear(key: ByteArray) {
        runCatching { preferences.removeKey(qualify(key)) }
            .getOrElse { throw HostRejection.Rejected("failed to clear core storage key: ${it.message}") }
    }

    private fun qualify(key: ByteArray) = "$CORE_NAMESPACE/${key.toHex()}"

    private companion object {
        const val CORE_NAMESPACE = "truapi/core"
    }
}

/** Namespace for one product's core-facing local storage. */
fun productStorageNamespace(productId: String): String = "truapi/product/$productId"

/**
 * `EncryptionUtil` reports both a failed encrypt and a failed decrypt by
 * returning an empty string, and it also refuses to encrypt an empty input, so
 * a write that silently failed is otherwise indistinguishable from a value that
 * is legitimately empty. Tagging the plaintext makes the two tellable apart: an
 * untagged read is a failure and must surface as a miss rather than as empty
 * bytes the core would treat as real.
 */
private const val VALUE_TAG = "v1:"

private fun readValue(preferences: EncryptedPreferences, key: String): ByteArray? {
    val stored = preferences.getDecryptedString(key) ?: return null
    if (!stored.startsWith(VALUE_TAG)) return null
    return decodeOrNull(stored.removePrefix(VALUE_TAG))
}

/** Returns null on success, or a reason to report to the core. */
private fun writeValue(preferences: EncryptedPreferences, key: String, value: ByteArray): String? {
    val tagged = VALUE_TAG + value.toHex()
    val failure = runCatching { preferences.putEncryptedString(key, tagged) }.exceptionOrNull()
    if (failure != null) return "failed to persist $key: ${failure.message}"

    // The encrypt path swallows its own exceptions, so the only reliable
    // signal that the value landed is reading it back.
    return if (preferences.getDecryptedString(key) == tagged) null else "failed to persist $key"
}

private fun storageFailure(reason: String): HostStorageException =
    HostStorageException.Storage(HostLocalStorageReadError.Unknown(reason))

@OptIn(ExperimentalStdlibApi::class)
private fun ByteArray.toHex(): String = toHexString()

@OptIn(ExperimentalStdlibApi::class)
private fun decodeOrNull(hex: String?): ByteArray? =
    hex?.let { runCatching { it.hexToByteArray() }.getOrNull() }
