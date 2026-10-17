package com.gerfautwallet.gerfaut

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID

// The provider of the files Gerfaut shares, a history or a backup. Its
// own class, so the manifest names it apart from any other FileProvider
// a plugin declares. Not exported: no app reaches a file through it but
// the one a share grants it to.
class SharedFileProvider : FileProvider()

// Told by the share sheet which app the user picked, if any: the one way
// to know a file went somewhere, the sheet itself answering nothing.
// Not exported: only the system reaches it, through the PendingIntent
// the sheet is handed. What it reads is the share's token, nothing more.
class ShareChosenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val token = intent?.getStringExtra(SharedFiles.EXTRA_TOKEN) ?: return
        SharedFiles.noteChosen(token)
    }
}

// Hands a file to the app the user picks in the share sheet, and to that
// app alone.
//
// Each share writes its file into a folder of its own under the cache,
// so no two shares ever have the same address: what was granted to one
// app for one file opens nothing shared after it, under the same name or
// not. The grant is a read, never a write, and goes with the intent: the
// system passes it from the share sheet to the app chosen there, and
// takes it back once that app is done with the screen it opened. No app
// is granted anything ahead of the choice.
//
// The answer waits for the sheet to close: true when an app was picked,
// false when the sheet was waved away.
//
// The copy stays an hour, for the app that reads it late (a mail left in
// drafts, a slow upload), then the sweep of lib/src/share.dart deletes
// it, folder and all.
internal object SharedFiles {
    // Under the cache, as res/xml/shared_paths.xml declares it.
    private const val FOLDER = "shared"

    const val EXTRA_TOKEN = "token"

    // The shares whose sheet named an app, by token, until asked.
    private val chosen = mutableSetOf<String>()

    fun noteChosen(token: String) {
        synchronized(chosen) { chosen.add(token) }
    }

    fun wasChosen(token: String): Boolean = synchronized(chosen) { token in chosen }

    // Whether the sheet of this share named an app; asked once.
    fun takeChosen(token: String): Boolean = synchronized(chosen) { chosen.remove(token) }

    // Writes the file and answers the share sheet to open on it, which
    // tells ShareChosenReceiver under [token] the app it hands the file
    // to. Off the main thread: the writing.
    fun prepare(
        activity: Activity,
        bytes: ByteArray,
        filename: String,
        mimeType: String,
        token: String,
    ): Intent {
        val file = write(activity, bytes, filename)
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.shared", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            // The grant travels with the clip: the share sheet hands it
            // on to the app chosen, as it does the intent.
            clipData = ClipData.newUri(activity.contentResolver, file.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val notice = Intent(activity, ShareChosenReceiver::class.java).putExtra(EXTRA_TOKEN, token)
        // Mutable, for the sheet to add the app it picked; explicit, so
        // nothing but this receiver can ever be reached through it.
        val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val told = PendingIntent.getBroadcast(
            activity,
            0,
            notice,
            PendingIntent.FLAG_UPDATE_CURRENT or mutable,
        )
        return Intent.createChooser(send, null, told.intentSender)
    }

    // The file of one share, under a folder no other share uses. The name
    // is the one the receiving app shows; anything in it that would climb
    // out of the folder is dropped.
    private fun write(activity: Activity, bytes: ByteArray, filename: String): File {
        val root = File(activity.cacheDir, FOLDER)
        val folder = File(root, UUID.randomUUID().toString())
        if (!folder.mkdirs()) throw IllegalStateException("the share folder could not be made")
        val name = File(filename).name.takeUnless { it.isBlank() || it == "." || it == ".." }
            ?: "shared"
        val file = File(folder, name)
        if (file.canonicalFile.parentFile != folder.canonicalFile) {
            throw IllegalArgumentException("the file name leaves its folder")
        }
        file.writeBytes(bytes)
        return file
    }
}
