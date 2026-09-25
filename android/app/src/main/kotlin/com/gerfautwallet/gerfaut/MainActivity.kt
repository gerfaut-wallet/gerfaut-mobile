package com.gerfautwallet.gerfaut

import android.app.Activity
import android.app.ActivityManager
import android.appwidget.AppWidgetManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import java.io.ByteArrayOutputStream
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

    // The file being picked: the call waiting for its bytes, and how
    // many it may have. One at a time.
    private var pendingOpen: PendingOpen? = null

    private val openDialog: ActivityResultLauncher<Intent> =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { outcome ->
            val uri = if (outcome.resultCode == Activity.RESULT_OK) outcome.data?.data else null
            val open = pendingOpen
            pendingOpen = null
            if (open == null) return@registerForActivityResult
            if (uri == null) {
                // Waved away: nothing was picked.
                open.result.success(null)
                return@registerForActivityResult
            }
            // A provider may fetch the file over the network: read off
            // the main thread, answer on it.
            Thread {
                val answer = try {
                    Result.success(readBounded(uri, open.maxBytes))
                } catch (error: Exception) {
                    Result.failure(error)
                }
                runOnUiThread {
                    answer.fold(
                        { open.result.success(it) },
                        { open.result.error("read_failed", it.message, null) },
                    )
                }
            }.start()
        }

    // The call waiting for the battery question to be answered.
    private var pendingExemption: MethodChannel.Result? = null

    private val exemptionDialog: ActivityResultLauncher<Intent> =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            // The result code says nothing here; the power manager does.
            val waiting = pendingExemption
            pendingExemption = null
            waiting?.success(isBatteryExempt())
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
                "copySensitive" -> {
                    val text = call.arguments as? String
                    if (text == null) {
                        result.error("bad_argument", "copySensitive takes a string", null)
                    } else {
                        copySensitive(text)
                        result.success(null)
                    }
                }
                "openInApp" -> {
                    val target = call.argument<String>("package")
                    val url = call.argument<String>("url")
                    if (target == null || url == null) {
                        result.error("bad_argument", "openInApp takes package and url", null)
                    } else {
                        result.success(openInApp(target, url))
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
                "openDocument" -> {
                    val mimeTypes = call.argument<List<String>>("mimeTypes")
                    val maxBytes = call.argument<Int>("maxBytes")
                    if (mimeTypes == null || maxBytes == null || maxBytes < 0) {
                        result.error(
                            "bad_argument",
                            "openDocument takes mimeTypes and maxBytes",
                            null,
                        )
                    } else {
                        openDocument(mimeTypes, maxBytes, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, LIVE_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // Called from a visible app, which is what lets a
                    // foreground service start at all.
                    "start" -> {
                        LiveService.setWanted(this, true)
                        result.success(LiveService.start(this))
                    }
                    "stop" -> {
                        LiveService.stop(this)
                        result.success(null)
                    }
                    "isRunning" -> result.success(LiveService.isRunning)
                    "isWanted" -> result.success(LiveService.isWanted(this))
                    "isBatteryExempt" -> result.success(isBatteryExempt())
                    "requestBatteryExemption" -> requestBatteryExemption(result)
                    "manufacturer" -> result.success(Build.MANUFACTURER ?: "")
                    "openAppSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("failed", error.message, null)
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

    // --- live watch -----------------------------------------------------

    private fun isBatteryExempt(): Boolean =
        (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .isIgnoringBatteryOptimizations(packageName)

    // Puts Android's own yes-or-no question to the user. Without the
    // exemption Android 12 and later will not let a killed service come
    // back by itself, which is the whole reason for asking. Where the
    // direct question is not to be had, the list it stands for opens
    // instead. Answers whether the app is exempt once the user is back.
    private fun requestBatteryExemption(result: MethodChannel.Result) {
        if (isBatteryExempt()) {
            result.success(true)
            return
        }
        if (pendingExemption != null) {
            result.error("busy", "the question is already on screen", null)
            return
        }
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"),
        )
        val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        for (intent in listOf(direct, list)) {
            pendingExemption = result
            try {
                exemptionDialog.launch(intent)
                return
            } catch (_: Exception) {
                pendingExemption = null
            }
        }
        result.success(false)
    }

    // Opens this app's own page in the system settings. Every maker
    // keeps its per-app battery switches there or one tap away, and no
    // app may flip them itself: the most it can do is open the page.
    // The one intent every Android has for it. Answers false when the
    // page did not open.
    private fun openAppSettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
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

    // Puts text on the clipboard, marked as something not to show.
    //
    // From Android 13 the system flashes a preview of everything copied
    // and keeps a history of it, both readable over the shoulder and
    // outside the app. A clip marked sensitive is shown as hidden there
    // and kept out of the history. Below 13 the extra means nothing and
    // this is an ordinary copy: the flag is all that changes, never
    // whether the copy happens.
    //
    // The label stays empty on purpose. It is what a clipboard manager
    // shows next to the entry, and an app that can wear a calculator's
    // face must not write its own name there.
    private fun copySensitive(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("", text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
        }
        clipboard.setPrimaryClip(clip)
    }

    // Hands a URL to one named app, and to no other. Answers false when
    // that app is not installed.
    //
    // An intent without a package is offered to every app that declared
    // the scheme, and the system asks the user to pick one. The links
    // that come through here carry an ntfy topic, which is the whole
    // secret of a channel: a chooser listing whatever app declared
    // `ntfy://` is a chooser for who reads the alerts of this account.
    // Naming the package is what keeps the topic between Gerfaut and
    // ntfy. It needs the <queries> entry in the manifest: without it
    // the package is invisible to this app and an installed ntfy looks
    // exactly like an absent one.
    private fun openInApp(target: String, url: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(target)
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    // Opens the system's save dialog on a new document and writes the
    // bytes to whatever place it names. Answers true once written,
    // false when the dialog was dismissed, and an error when the dialog
    // could not open at all.
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
        } catch (error: Exception) {
            // Whatever kept the dialog from opening, no result is coming
            // back for this save. The slot is freed before the caller is
            // told, or every later save would be refused as busy for as
            // long as this activity lives.
            pendingSave = null
            if (error is ActivityNotFoundException) {
                result.error("unavailable", "no app on this device can save a file", null)
            } else {
                result.error(
                    "failed",
                    error.message ?: "the save dialog could not be opened",
                    null,
                )
            }
        }
    }

    // Opens the system's open-document dialog and answers with the file
    // it names: its name, its size, and its bytes when there are no more
    // than maxBytes of them. A larger file comes back without its bytes,
    // having been read no further than the limit: the file picker plugin
    // reads every byte into memory before its caller sees the size, and
    // a video picked by mistake is enough to end the app. Answers null
    // when the dialog was dismissed.
    private fun openDocument(
        mimeTypes: List<String>,
        maxBytes: Int,
        result: MethodChannel.Result,
    ) {
        if (pendingOpen != null) {
            result.error("busy", "a file is already being picked", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            when (mimeTypes.size) {
                0 -> type = "*/*"
                1 -> type = mimeTypes.first()
                else -> {
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                }
            }
        }
        pendingOpen = PendingOpen(maxBytes, result)
        try {
            openDialog.launch(intent)
        } catch (error: Exception) {
            pendingOpen = null
            if (error is ActivityNotFoundException) {
                result.error("unavailable", "no app on this device can open a file", null)
            } else {
                result.error("failed", error.message ?: "the file dialog could not be opened", null)
            }
        }
    }

    // What openDocument answers for one file. The size the provider
    // states is trusted only to refuse early: the bytes are counted as
    // they come, and the reading stops one past the limit.
    private fun readBounded(uri: Uri, maxBytes: Int): Map<String, Any?> {
        var name: String? = null
        var stated: Long? = null
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) stated = cursor.getLong(sizeIndex)
            }
        }
        val statedSize = stated
        if (statedSize != null && statedSize > maxBytes) {
            return mapOf("name" to name, "size" to statedSize, "bytes" to null)
        }
        val stream = contentResolver.openInputStream(uri)
            ?: throw IOException("the file could not be opened")
        val out = ByteArrayOutputStream()
        stream.use { input ->
            val buffer = ByteArray(64 * 1024)
            while (out.size() <= maxBytes) {
                val read = input.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
            }
        }
        if (out.size() > maxBytes) {
            return mapOf("name" to name, "size" to out.size().toLong(), "bytes" to null)
        }
        val bytes = out.toByteArray()
        return mapOf("name" to name, "size" to bytes.size.toLong(), "bytes" to bytes)
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
        // A permanent notification headed "Gerfaut" is the opposite of a
        // disguise. The Dart side turns Live off before it asks for the
        // calculator; this says the same thing a second time, on purpose.
        if (disguised) LiveService.stop(this)
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

    private class PendingOpen(val maxBytes: Int, val result: MethodChannel.Result)

    private companion object {
        const val WINDOW_CHANNEL = "gerfaut/window"
        const val FILES_CHANNEL = "gerfaut/files"
        const val DISGUISE_CHANNEL = "gerfaut/disguise"
        const val LIVE_CHANNEL = "gerfaut/live"
        const val DISGUISE_MARKER = "disguised"
        const val CALCULATOR_LIGHT = 0xFFF5F5F5.toInt()
        const val CALCULATOR_DARK = 0xFF121212.toInt()
    }
}
