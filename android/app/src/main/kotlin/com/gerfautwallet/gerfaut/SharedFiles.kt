package com.gerfautwallet.gerfaut

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID

// The provider of the files Gerfaut shares, a history or a backup. Its
// own class, so the manifest names it apart from any other FileProvider
// a plugin declares. Not exported: no app reaches a file through it but
// the one a share grants it to.
class SharedFileProvider : FileProvider()

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
// The copy stays an hour, for the app that reads it late (a mail left in
// drafts, a slow upload), then the sweep of lib/src/share.dart deletes
// it, folder and all.
internal object SharedFiles {
    // Under the cache, as res/xml/shared_paths.xml declares it.
    private const val FOLDER = "shared"

    // Writes the file and answers the share sheet to open on it. Off the
    // main thread: the writing.
    fun prepare(activity: Activity, bytes: ByteArray, filename: String, mimeType: String): Intent {
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
        return Intent.createChooser(send, null)
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
