package com.gerfautwallet.gerfaut

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

// A fragment activity, which is what the biometric prompt attaches to.
class MainActivity : FlutterFragmentActivity() {
    // The save under way: the bytes to write once the picker names a
    // place, and the call waiting for the answer. One at a time.
    private var pendingSave: PendingSave? = null

    // Registered as a field, before the activity starts, the way the
    // result API requires.
    private val saveDialog: ActivityResultLauncher<Intent> =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { outcome ->
            val save = pendingSave ?: return@registerForActivityResult
            pendingSave = null
            val uri = outcome.data?.data
            if (outcome.resultCode != Activity.RESULT_OK || uri == null) {
                // Waved away: nothing was written anywhere.
                save.result.success(false)
                return@registerForActivityResult
            }
            try {
                val stream = contentResolver.openOutputStream(uri, "wt")
                    ?: throw IOException("the document could not be opened for writing")
                stream.use { it.write(save.bytes) }
                save.result.success(true)
            } catch (error: Exception) {
                save.result.error("write_failed", error.message, null)
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, WINDOW_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val secure = call.arguments as? Boolean
                    if (secure == null) {
                        result.error("bad_argument", "setSecure takes a boolean", null)
                    } else {
                        setSecure(secure)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, FILES_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "createDocument" -> {
                    val filename = call.argument<String>("filename")
                    val mimeType = call.argument<String>("mimeType")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (filename == null || mimeType == null || bytes == null) {
                        result.error(
                            "bad_argument",
                            "createDocument takes filename, mimeType and bytes",
                            null,
                        )
                    } else {
                        createDocument(filename, mimeType, bytes, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // FLAG_SECURE blanks this window in screenshots, in screen
    // recordings and in the task switcher's thumbnail. The Dart side
    // sets it only while an app lock exists: the thumbnail is taken
    // before the lock screen draws, so the lock alone leaves a balance
    // readable there; without a lock the user keeps the right to
    // capture their own screen.
    private fun setSecure(secure: Boolean) {
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    // Opens the system's save dialog on a new document and writes the
    // bytes to whatever place it names. Answers true once written,
    // false when the dialog was dismissed.
    private fun createDocument(
        filename: String,
        mimeType: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (pendingSave != null) {
            result.error("busy", "a save is already under way", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        pendingSave = PendingSave(bytes, result)
        try {
            saveDialog.launch(intent)
        } catch (error: ActivityNotFoundException) {
            pendingSave = null
            result.error("unavailable", "no app on this device can save a file", null)
        }
    }

    private class PendingSave(val bytes: ByteArray, val result: MethodChannel.Result)

    private companion object {
        const val WINDOW_CHANNEL = "gerfaut/window"
        const val FILES_CHANNEL = "gerfaut/files"
    }
}
