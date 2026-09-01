package com.gerfautwallet.gerfaut

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A fragment activity, which is what the biometric prompt attaches to.
class MainActivity : FlutterFragmentActivity() {
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

    private companion object {
        const val WINDOW_CHANNEL = "gerfaut/window"
    }
}
