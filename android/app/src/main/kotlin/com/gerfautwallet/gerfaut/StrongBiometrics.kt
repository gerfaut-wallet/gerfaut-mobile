package com.gerfautwallet.gerfaut

import android.os.Build
import android.os.Handler
import android.os.Looper
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
        if (pending != null) {
            // Another prompt is up: this one is refused at once, and the
            // key that prompt opens is left alone.
            result.success(false)
            return
        }
        val key = try {
            createKey()
            loadKey() ?: throw IllegalStateException("the key was not kept")
        } catch (_: Exception) {
            forget()
            result.success(false)
            return
        }
        // Not carried over a trip to the background: coming back locks
        // the app, and the switch that asked is no longer on screen.
        prompt(key, title, cancel, persist = false) { passed ->
            if (!passed) forget()
            result.success(passed)
        }
    }

    // The prompt on the key in place: "passed", "refused" (cancelled,
    // or not answered), or "reset" when there is no key to unlock any
    // more, the biometrics of the phone having changed since it was made.
    fun authenticate(title: String, cancel: String, result: MethodChannel.Result) {
        val key = try {
            loadKey()
        } catch (_: Exception) {
            result.success("refused")
            return
        }
        if (key == null) {
            result.success("reset")
            return
        }
        try {
            cipherFor(key)
        } catch (_: KeyPermanentlyInvalidatedException) {
            forget()
            result.success("reset")
            return
        } catch (_: Exception) {
            result.success("refused")
            return
        }
        prompt(key, title, cancel, persist = true) { passed ->
            result.success(if (passed) "passed" else "refused")
        }
    }

    // Drops the key: the biometric no longer opens anything.
    fun forget() {
        try {
            keyStore().deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
            // Nothing to drop.
        }
    }

    // The activity's own moments, which a prompt has to follow.
    fun onPause() {
        paused = true
        // A prompt the system cancelled a moment ago went with the app.
        pending?.let { if (it.cancelled) it.resumeWanted = true }
    }

    fun onResume() {
        paused = false
        val waiting = pending ?: return
        if (waiting.resumeWanted) {
            waiting.resumeWanted = false
            waiting.cancelled = false
            show(waiting)
        }
    }

    fun onDestroy() {
        pending?.let { finish(it, false) }
    }

    // The prompt asked for and not answered yet. One at a time: androidx
    // keeps one prompt state per activity, and a second prompt would
    // take the first one's answer away, leaving its caller waiting for
    // good. A second ask is refused at once instead.
    private var pending: Pending? = null

    // The activity is behind something: the launcher, or the face
    // unlock some phones draw over it while the camera reads.
    private var paused = false

    private class Pending(
        val key: SecretKey,
        val title: String,
        val cancel: String,
        // Shown again when the app comes back, if a trip to the
        // background cancelled it.
        val persist: Boolean,
        val done: (Boolean) -> Unit,
    ) {
        var answered = false
        var resumeWanted = false

        // Cancelled by the system, and not answered yet: a pause coming
        // right after says the app was leaving.
        var cancelled = false
    }

    private val main = Handler(Looper.getMainLooper())

    private fun prompt(
        key: SecretKey,
        title: String,
        cancel: String,
        persist: Boolean,
        done: (Boolean) -> Unit,
    ) {
        if (pending != null) {
            done(false)
            return
        }
        val waiting = Pending(key, title, cancel, persist, done)
        pending = waiting
        show(waiting)
    }

    // Puts the prompt up, or answers at once: every path ends in an
    // answer, now or once the app is back.
    private fun show(waiting: Pending) {
        if (activity.supportFragmentManager.isStateSaved) {
            // androidx would return without a word: the activity is on
            // its way out of sight.
            if (waiting.persist && paused) {
                waiting.resumeWanted = true
            } else {
                finish(waiting, false)
            }
            return
        }
        val cipher = try {
            cipherFor(waiting.key)
        } catch (_: Exception) {
            finish(waiting, false)
            return
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
                finish(waiting, used)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                // Cancelled by a trip to the background, not by the
                // user's "Cancel": asked again when the app is back. The
                // cancel may come a moment before the pause (Android 16
                // reports the home gesture as the user's), so it waits a
                // beat for one before it counts as a refusal.
                val leaving = errorCode == BiometricPrompt.ERROR_CANCELED ||
                    errorCode == BiometricPrompt.ERROR_USER_CANCELED
                if (waiting.persist && leaving) {
                    if (paused) {
                        waiting.resumeWanted = true
                        return
                    }
                    waiting.cancelled = true
                    main.postDelayed({
                        if (!waiting.resumeWanted) finish(waiting, false)
                    }, LEAVING_GRACE_MS)
                    return
                }
                finish(waiting, false)
            }

            // A finger not recognised: the prompt stays up for another.
            override fun onAuthenticationFailed() {}
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(waiting.title)
            .setNegativeButtonText(waiting.cancel)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            // A face seen is not yet a yes: the prompt waits for a tap, so
            // a phone held up to its owner opens nothing by itself.
            .setConfirmationRequired(true)
            .build()
        try {
            BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
                .authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (_: Exception) {
            finish(waiting, false)
        }
    }

    private fun finish(waiting: Pending, passed: Boolean) {
        if (waiting.answered) return
        waiting.answered = true
        if (pending === waiting) pending = null
        waiting.done(passed)
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

        // How long a cancelled prompt waits for the pause that would say
        // the app was leaving.
        const val LEAVING_GRACE_MS = 500L

        // A plain name: a list of the Keystore's aliases must not say
        // what the key opens.
        const val KEY_ALIAS = "unlock"

        // What the key encrypts once, to show it was unlocked. Thrown
        // away at once.
        val CHALLENGE = ByteArray(16)
    }
}
