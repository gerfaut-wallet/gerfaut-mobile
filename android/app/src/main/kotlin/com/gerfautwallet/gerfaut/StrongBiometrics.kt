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
//
// This side only puts one prompt up and says how it ended. What an end
// means, a refusal or a trip away to come back from, is decided by the
// Dart side (PromptSession, lib/src/lock.dart), which sees the app's
// whole lifecycle.
internal class StrongBiometrics(private val activity: FragmentActivity) {

    // What the phone offers: "strong"; "weak" when the only biometric set
    // up is a weak one; "none" when no strong one can be had (none set
    // up, no sensor); "unavailable" when a strong one may be there but
    // cannot answer right now (the sensor busy or held, an update due):
    // a passing state that changes nothing.
    fun support(): String {
        val manager = BiometricManager.from(activity)
        val strong = manager.canAuthenticate(BIOMETRIC_STRONG)
        if (strong == BiometricManager.BIOMETRIC_SUCCESS) return "strong"
        // Android answers "unavailable" for strong when the sensor is
        // there but rated weak, as for one that cannot answer right now:
        // a weak biometric that works tells the two apart.
        val weak = manager.canAuthenticate(BIOMETRIC_WEAK)
        if (weak == BiometricManager.BIOMETRIC_SUCCESS) return "weak"
        val passing = setOf(
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE,
            BiometricManager.BIOMETRIC_STATUS_UNKNOWN,
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED,
        )
        return if (strong in passing || weak in passing) "unavailable" else "none"
    }

    // A new key in place of any other, for turning biometrics on: the
    // prompt that follows confirms it, or the key is forgotten.
    fun prepareKey(): Boolean {
        if (attempt != null) return false
        return try {
            createKey()
            loadKey() != null
        } catch (_: Exception) {
            forget()
            false
        }
    }

    // Whether a key is there for the prompt to unlock, without asking
    // for anything: "present", "absent" when the Keystore was read and
    // holds none (a vault that turned biometrics on before keys were
    // made, which simply has to turn them on again), or "unknown" when
    // it could not be read, a Keystore not ready yet after the phone
    // started: no proof of anything.
    fun keyPresence(): String = try {
        if (loadKey() != null) "present" else "absent"
    } catch (_: Exception) {
        "unknown"
    }

    // Drops the key: the biometric no longer opens anything.
    fun forget() {
        try {
            keyStore().deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
            // Nothing to drop.
        }
    }

    // One prompt on the key in place, answered once, with how it ended:
    //   "passed"   a strong biometric unlocked the key, and it was used;
    //   "missing"  there is no key;
    //   "reset"    the key no longer opens: the phone's biometrics changed;
    //   "busy"     another prompt is up (androidx keeps one per activity,
    //              and a second would take the first one's answer away);
    //   "unshown"  the activity was on its way out of sight, and androidx
    //              would have shown nothing and said nothing;
    //   "gone"     the activity went away with the prompt up;
    //   "error:N"  the prompt closed on androidx error N, a cancel included;
    //   "refused"  anything else that kept it from opening.
    fun prompt(title: String, cancel: String, result: MethodChannel.Result) {
        if (attempt != null) {
            result.success("busy")
            return
        }
        val key = try {
            loadKey()
        } catch (_: Exception) {
            result.success("refused")
            return
        }
        if (key == null) {
            result.success("missing")
            return
        }
        val cipher = try {
            cipherFor(key)
        } catch (_: KeyPermanentlyInvalidatedException) {
            forget()
            result.success("reset")
            return
        } catch (_: Exception) {
            result.success("refused")
            return
        }
        if (activity.supportFragmentManager.isStateSaved) {
            result.success("unshown")
            return
        }
        val current = Attempt(result)
        attempt = current
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(outcome: BiometricPrompt.AuthenticationResult) {
                // The key works only for a biometric the Keystore took:
                // a success that cannot use it is no success.
                val used = try {
                    outcome.cryptoObject?.cipher?.doFinal(CHALLENGE) != null
                } catch (_: Exception) {
                    false
                }
                end(current, if (used) "passed" else "refused")
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                end(current, "error:$errorCode")
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
            end(current, "refused")
        }
    }

    // The activity is going: a prompt still up is answered, for nobody to
    // wait on an activity that is gone.
    fun onDestroy() {
        attempt?.let { end(it, "gone") }
    }

    // The prompt up, if any, and the call waiting for how it ends.
    private var attempt: Attempt? = null

    private class Attempt(val result: MethodChannel.Result) {
        var answered = false
    }

    private fun end(current: Attempt, outcome: String) {
        if (current.answered) return
        current.answered = true
        if (attempt === current) attempt = null
        current.result.success(outcome)
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
