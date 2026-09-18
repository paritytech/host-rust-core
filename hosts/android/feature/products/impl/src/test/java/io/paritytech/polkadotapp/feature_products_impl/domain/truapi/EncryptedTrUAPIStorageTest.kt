package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.paritytech.polkadotapp.common.data.storage.preferences.encrypted.EncryptedPreferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import uniffi.truapi_server.HostStorageException

class EncryptedTrUAPIStorageTest {
    private val prefs = FakeEncryptedPreferences()

    @Test
    fun `an empty value is a value, not a miss`() {
        val storage = EncryptedHostStorage(prefs, productStorageNamespace("a.dot"))

        storage.write("k", ByteArray(0))

        assertNotNull("empty payload must read back as empty, not null", storage.read("k"))
        assertArrayEquals(ByteArray(0), storage.read("k"))
    }

    /** `EncryptionUtil` returns "" instead of throwing when encryption fails. */
    @Test
    fun `a silently failed write is reported`() {
        val storage = EncryptedHostStorage(prefs.swallowingWrites(), productStorageNamespace("a.dot"))

        assertThrows(HostStorageException::class.java) { storage.write("k", byteArrayOf(9)) }
    }

    @Test
    fun `an undecryptable value reads as a miss, not empty bytes`() {
        val storage = EncryptedHostStorage(prefs, productStorageNamespace("a.dot"))
        storage.write("k", byteArrayOf(9))
        prefs.corrupt()

        assertNull(storage.read("k"))
    }

    @Test
    fun `products cannot read each other's keys`() {
        EncryptedHostStorage(prefs, productStorageNamespace("a.dot")).write("shared", byteArrayOf(7))

        assertNull(EncryptedHostStorage(prefs, productStorageNamespace("b.dot")).read("shared"))
    }

    @Test
    fun `core storage is shared across products by design`() {
        val first = EncryptedHostCoreStorage(prefs)
        first.write(byteArrayOf(1), byteArrayOf(42))

        assertArrayEquals(byteArrayOf(42), EncryptedHostCoreStorage(prefs).read(byteArrayOf(1)))
    }
}

private class FakeEncryptedPreferences(
    private val dropWrites: Boolean = false,
) : EncryptedPreferences {
    private val values = mutableMapOf<String, String>()

    /** Mirrors EncryptionUtil storing "" when it cannot encrypt. */
    fun swallowingWrites() = FakeEncryptedPreferences(dropWrites = true)

    fun corrupt() = values.keys.forEach { values[it] = "" }

    override fun putEncryptedString(field: String, value: String) {
        values[field] = if (dropWrites) "" else value
    }

    override fun getDecryptedString(field: String): String? = values[field]

    override fun hasKey(field: String): Boolean = values.containsKey(field)

    override fun removeKey(field: String) {
        values.remove(field)
    }

    override fun decryptedStringFlow(field: String): Flow<String?> = flowOf(values[field])
}
