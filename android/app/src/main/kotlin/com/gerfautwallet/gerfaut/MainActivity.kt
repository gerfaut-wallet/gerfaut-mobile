package com.gerfautwallet.gerfaut

import android.app.Activity
import android.app.ActivityManager
import android.appwidget.AppWidgetManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
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
            val uri = if (outcome.resultCode == Activity.RESULT_OK) outcome.data?.data else null
            val save = pendingSave
            pendingSave = null
            if (save == null) {
                // The activity was recreated while the dialog was up and
                // the bytes went with it: nobody is waiting for an answer,
                // and the empty document the picker created must not stay
                // under the name the user chose.
                if (uri != null) discardDocument(uri)
                return@registerForActivityResult
            }
            if (uri == null) {
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
                // An empty or half-written file under the chosen name would
                // pass for the export: it goes before the failure is told.
                discardDocument(uri)
                save.result.error("write_failed", error.message, null)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The task switcher must show the calculator from the first frame
        // of a disguised app, before the Dart side has asked anything.
        applyTaskDescription(isDisguised())
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
        MethodChannel(messenger, DISGUISE_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isDisguised" -> result.success(isDisguised())
                    "setDisguised" -> {
                        val disguised = call.arguments as? Boolean
                        if (disguised == null) {
                            result.error("bad_argument", "setDisguised takes a boolean", null)
                        } else {
                            setDisguised(disguised)
                            result.success(null)
                        }
                    }
                    "setWidgetsEnabled" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("bad_argument", "setWidgetsEnabled takes a boolean", null)
                        } else {
                            setWidgetsEnabled(enabled)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("failed", error.message, null)
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

    // Removes a document the picker created for a save that did not
    // happen. Best effort: a provider that will not delete leaves an
    // empty file behind, and the error already reported says the save
    // failed.
    private fun discardDocument(uri: Uri) {
        try {
            DocumentsContract.deleteDocument(contentResolver, uri)
        } catch (_: Exception) {
            // Nothing more can be done about it from here.
        }
    }

    // --- the disguise ---------------------------------------------------
    //
    // Disguised, Gerfaut is a calculator in the launcher and in the task
    // switcher. On Android 10 and later an app that disables its only
    // launcher entry does not disappear from the launcher: the system
    // shows a synthesized entry in its place, named after the app and
    // opening its settings page. Hiding the icon would therefore still
    // say "Gerfaut". So the disguise is a swap between two aliases of
    // this activity, one wearing the app's own name and icon, the other
    // a calculator's, exactly one enabled at a time. The package manager
    // remembers which, across restarts and updates, which makes it the
    // one source of truth: nothing in the vault says whether the app is
    // disguised, so a backup restored elsewhere cannot claim it is.

    private val launcherAlias: ComponentName
        get() = ComponentName(this, "$packageName.Launcher")

    private val calculatorAlias: ComponentName
        get() = ComponentName(this, "$packageName.Calculator")

    // The background isolate has no activity to ask, so the answer is
    // also kept as a marker file beside the app's data, written whenever
    // the aliases flip and brought back in line each time it is read.
    private val disguiseMarker: File
        get() = File(filesDir, DISGUISE_MARKER)

    // The channel-facing read: it also brings the marker in line, so
    // the background isolate reads the same answer. Kept off the hot
    // path — the task-description override reads without writing.
    private fun isDisguised(): Boolean {
        val disguised = readDisguised()
        writeMarker(disguised)
        return disguised
    }

    private fun readDisguised(): Boolean =
        packageManager.getComponentEnabledSetting(calculatorAlias) ==
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    private fun setDisguised(disguised: Boolean) {
        val shown = if (disguised) calculatorAlias else launcherAlias
        val hidden = if (disguised) launcherAlias else calculatorAlias
        // The new entry first: the launcher never sees a moment with
        // neither. DONT_KILL_APP, or the swap would end the very screen
        // asking for it.
        packageManager.setComponentEnabledSetting(
            shown,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        packageManager.setComponentEnabledSetting(
            hidden,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        writeMarker(disguised)
        applyTaskDescription(disguised)
    }

    private fun writeMarker(disguised: Boolean) {
        try {
            if (disguised) {
                disguiseMarker.createNewFile()
            } else {
                disguiseMarker.delete()
            }
        } catch (_: IOException) {
            // A marker that cannot be written costs one notification in
            // the background at worst; the activity still knows.
        }
    }

    // Every widget provider of the app, found by the meta-data that
    // makes a receiver one and never by name, so a widget added later is
    // covered without touching this file. Disabled, its widgets leave
    // the home screen; enabled again means back to what the manifest
    // says, which is the only state a widget can be added from.
    private fun setWidgetsEnabled(enabled: Boolean) {
        val flags = PackageManager.GET_RECEIVERS or
            PackageManager.GET_META_DATA or
            PackageManager.MATCH_DISABLED_COMPONENTS
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, flags)
        }
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        for (receiver in info.receivers ?: return) {
            val provides = receiver.metaData
                ?.containsKey(AppWidgetManager.META_DATA_APPWIDGET_PROVIDER)
            if (provides != true) continue
            packageManager.setComponentEnabledSetting(
                ComponentName(packageName, receiver.name),
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    // The primary colour Flutter last asked the task switcher to use.
    private var taskColor: Int = 0

    // Flutter sets the task description itself, from the app's title,
    // every time it builds its Title widget, and clears the icon while
    // at it. Whatever it asks for, the task wears the face in force:
    // only the colour it chose is kept.
    override fun setTaskDescription(taskDescription: ActivityManager.TaskDescription?) {
        taskColor = taskDescription?.primaryColor ?: taskColor
        super.setTaskDescription(describeTask(readDisguised()))
    }

    private fun applyTaskDescription(disguised: Boolean) {
        super.setTaskDescription(describeTask(disguised))
    }

    // What the task switcher calls this task, and the icon it gives it.
    // Both are read from the alias in force, so the manifest stays the
    // one place that names either face.
    private fun describeTask(disguised: Boolean): ActivityManager.TaskDescription? {
        val alias = if (disguised) calculatorAlias else launcherAlias
        val info: ActivityInfo = try {
            packageManager.getActivityInfo(alias, PackageManager.MATCH_DISABLED_COMPONENTS)
        } catch (_: PackageManager.NameNotFoundException) {
            return null
        }
        val label = info.loadLabel(packageManager).toString()
        // The colour Flutter gives is the wallet's accent, and a card
        // named "Calculator" must not wear it: disguised, the switcher
        // gets the calculator's own background instead. The
        // three-argument forms reject a colour that is not opaque, and
        // Flutter often has none to give: the colour is kept only when
        // it is one the switcher would accept.
        val color = if (disguised) calculatorBackground() else taskColor
        val opaque = android.graphics.Color.alpha(color) == 0xFF
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            if (opaque) {
                ActivityManager.TaskDescription(label, info.iconResource, color)
            } else {
                ActivityManager.TaskDescription(label, info.iconResource)
            }
        } else {
            val icon = info.loadIcon(packageManager)
            val size = resources.getDimensionPixelSize(android.R.dimen.app_icon_size)
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            icon.setBounds(0, 0, size, size)
            icon.draw(Canvas(bitmap))
            @Suppress("DEPRECATION")
            if (opaque) {
                ActivityManager.TaskDescription(label, bitmap, color)
            } else {
                ActivityManager.TaskDescription(label, bitmap)
            }
        }
    }

    // The background of the calculator screen in the theme in force:
    // the grey any stock calculator has. Mirrors the palette in
    // lib/screens/calculator.dart, which is the one place it is chosen.
    private fun calculatorBackground(): Int {
        val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return if (night == Configuration.UI_MODE_NIGHT_YES) CALCULATOR_DARK else CALCULATOR_LIGHT
    }

    private class PendingSave(val bytes: ByteArray, val result: MethodChannel.Result)

    private companion object {
        const val WINDOW_CHANNEL = "gerfaut/window"
        const val FILES_CHANNEL = "gerfaut/files"
        const val DISGUISE_CHANNEL = "gerfaut/disguise"
        const val DISGUISE_MARKER = "disguised"
        const val CALCULATOR_LIGHT = 0xFFF5F5F5.toInt()
        const val CALCULATOR_DARK = 0xFF121212.toInt()
    }
}
