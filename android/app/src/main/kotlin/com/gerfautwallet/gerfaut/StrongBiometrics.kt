package com.gerfautwallet.gerfaut

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

// The phone's own prompt, as the app lock may use it: a strong (class 3)
// biometric only, and only through a key of the Android Keystore that
// such a biometric alone unlocks.
//
// Android rates each sensor. A weak (class 2) one, most face unlocks
// that read a plain camera, can be fooled by a photograph, and the
// Keystore will not let it unlock a key: a prompt bound to a key cannot
// be answered by one. The key is also dropped by the Keystore the moment
// a fingerprint or a face is added on the phone, so whoever knows the
// phone's screen lock cannot enrol their own finger and walk in: the
// app asks for its secret again, and the user turns biometrics back on.
//
// Gerfaut never sees the biometric; the key encrypts nothing kept
// anywhere. Using it once after the prompt is the proof the prompt was
// answered by a biometric the Keystore accepts.
internal class StrongBiometrics(private val activity: FragmentActivity) {

    // What the phone offers: "strong", "weak" when the only biometric
    // set up is a weak one, or "none".
    fun support(): String {
        val manager = BiometricManager.from(activity)
        return when {
            manager.canAuthenticate(BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS -> "strong"
            manager.canAuthenticate(BIOMETRIC_WEAK) == BiometricManager.BIOMETRIC_SUCCESS -> "weak"
            else -> "none"
        }
    }

    // A new key, then the prompt on it: true once the phone confirmed.
    // A key the prompt did not confirm is not kept.
    fun enroll(title: String, cancel: String, result: MethodChannel.Result) {
        val cipher = try {
            createKey()
            cipherFor(loadKey() ?: throw IllegalStateException("the key was not kept"))
        } catch (_: Exception) {
            forget()
            result.success(false)
            return
        }
        prompt(cipher, title, cancel) { passed ->
            if (!passed) forget()
            result.success(passed)
        }
    }

    // The prompt on the key in place: "passed", "refused" (cancelled,
    // or not answered), or "reset" when there is no key to unlock any
    // more, the biometrics of the phone having changed since it was made.
    fun authenticate(title: String, cancel: String, result: MethodChannel.Result) {
        val cipher = try {
            val key = loadKey()
            if (key == null) {
                result.success("reset")
                return
            }
            cipherFor(key)
        } catch (_: KeyPermanentlyInvalidatedException) {
            forget()
            result.success("reset")
            return
        } catch (_: Exception) {
            result.success("refused")
            return
        }
        prompt(cipher, title, cancel) { passed -> result.success(if (passed) "passed" else "refused") }
    }

    // Drops the key: the biometric no longer opens anything.
    fun forget() {
        try {
            keyStore().deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
            // Nothing to drop.
        }
    }

    private fun prompt(
        cipher: Cipher,
        title: String,
        cancel: String,
        done: (Boolean) -> Unit,
    ) {
        var answered = false
        fun answer(passed: Boolean) {
            if (answered) return
            answered = true
            done(passed)
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(outcome: BiometricPrompt.AuthenticationResult) {
                // The key works only for a biometric the Keystore took:
                // a success that cannot use it is no success.
                val used = try {
                    outcome.cryptoObject?.cipher?.doFinal(CHALLENGE) != null
                } catch (_: Exception) {
                    false
                }
                answer(used)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                answer(false)
            }

            // A finger not recognised: the prompt stays up for another.
            override fun onAuthenticationFailed() {}
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setNegativeButtonText(cancel)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            // A face seen is not yet a yes: the prompt waits for a tap, so
            // a phone held up to its owner opens nothing by itself.
            .setConfirmationRequired(true)
            .build()
        try {
            BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
                .authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (_: Exception) {
            answer(false)
        }
    }

    private fun createKey() {
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Every use asks again, and only a strong biometric answers.
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            // The same before Android 11: -1 is "every use", and a key
            // bound that way takes nothing but a strong biometric.
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(builder.build())
        generator.generateKey()
    }

    private fun loadKey(): SecretKey? = keyStore().getKey(KEY_ALIAS, null) as? SecretKey

    private fun cipherFor(key: SecretKey): Cipher =
        Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"

        // A plain name: a list of the Keystore's aliases must not say
        // what the key opens.
        const val KEY_ALIAS = "unlock"

        // What the key encrypts once, to show it was unlocked. Thrown
        // away at once.
        val CHALLENGE = ByteArray(16)
    }
}
