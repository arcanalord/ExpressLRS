package org.fpvclub.mesh

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore-backed encryption boundary for sensitive local app records.
 *
 * The AES key is non-exportable through this API. Dart sends/receives record
 * plaintext but never receives key material. File purpose is authenticated as
 * AES-GCM AAD so a ciphertext cannot be silently moved between stores.
 */
class SecureStorageCipher {
    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "mesh_messenger_local_storage_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val TAG_BITS = 128
        private const val B64_FLAGS = Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
        private val ALLOWED_PURPOSES = setOf(
            "contacts",
            "groups",
            "group_receipts",
            "messages",
            "outbox",
        )
    }

    private val keyStore: KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun key(): SecretKey {
        val existing = keyStore.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun requirePurpose(purpose: String) {
        require(purpose in ALLOWED_PURPOSES) { "Unsupported secure-storage purpose" }
    }

    private fun aad(purpose: String): ByteArray =
        "mesh-messenger-local-storage:v1:$purpose".toByteArray(StandardCharsets.UTF_8)

    private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, B64_FLAGS)

    private fun decode(value: String): ByteArray = Base64.decode(value, B64_FLAGS)

    fun encrypt(purpose: String, plaintext: String): Map<String, String> {
        requirePurpose(purpose)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(aad(purpose))
        val ciphertext = cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8))
        return mapOf(
            "purpose" to purpose,
            "iv" to encode(cipher.iv),
            "ciphertext" to encode(ciphertext),
        )
    }

    fun decrypt(
        purpose: String,
        ivBase64: String,
        ciphertextBase64: String,
    ): String {
        requirePurpose(purpose)
        val iv = decode(ivBase64)
        require(iv.size == 12) { "Invalid AES-GCM IV" }
        val ciphertext = decode(ciphertextBase64)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(TAG_BITS, iv),
        )
        cipher.updateAAD(aad(purpose))
        return String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
    }
}
