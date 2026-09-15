package io.paritytech.polkadotapp.common.data.encryption

import io.paritytech.polkadotapp.common.domain.model.AeadKey
import io.paritytech.polkadotapp.common.utils.requireBouncyCastle
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

interface MessageEncryption {
    companion object;

    fun encrypt(plainMessage: ByteArray): ByteArray
    fun decrypt(encrypted: ByteArray): ByteArray
}

fun MessageEncryption.Companion.chaCha20Poly1305(key: AeadKey): MessageEncryption {
    return ChaCha20Poly1305MessageEncryption(key)
}

private class ChaCha20Poly1305MessageEncryption(key: AeadKey) : MessageEncryption {
    companion object {
        private const val TRANSFORMATION = "CHACHA20-POLY1305"
        private const val NONCE_LENGTH_BYTES = 12
    }

    private val keySpec = SecretKeySpec(key.bytes.value, "ChaCha20")

    override fun encrypt(plainMessage: ByteArray): ByteArray {
        val cipher = cipher()
        val nonce = ByteArray(NONCE_LENGTH_BYTES).apply { SecureRandom().nextBytes(this) }

        cipher.init(Cipher.ENCRYPT_MODE, keySpec, IvParameterSpec(nonce))
        val cipherText = cipher.doFinal(plainMessage)

        return nonce + cipherText
    }

    override fun decrypt(encrypted: ByteArray): ByteArray {
        val cipher = cipher()
        val nonce = encrypted.copyOfRange(0, NONCE_LENGTH_BYTES)
        val cipherText = encrypted.copyOfRange(NONCE_LENGTH_BYTES, encrypted.size)

        cipher.init(Cipher.DECRYPT_MODE, keySpec, IvParameterSpec(nonce))
        return cipher.doFinal(cipherText)
    }

    private fun cipher(): Cipher {
        requireBouncyCastle()

        return Cipher.getInstance(TRANSFORMATION, BouncyCastleProvider.PROVIDER_NAME)
    }
}
