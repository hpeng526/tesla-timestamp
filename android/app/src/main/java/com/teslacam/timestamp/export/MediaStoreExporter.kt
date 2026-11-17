package com.teslacam.timestamp.export

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Copies a finished MP4 into the phone gallery so it shows up in Photos / Files and stays after the
 * app cache is cleared. On Android 10+ this goes through MediaStore (no storage permission needed),
 * on Android 8/9 it falls back to the public Movies folder plus a media scan.
 */
object MediaStoreExporter {

    const val RELATIVE_FOLDER = "Movies/TeslaTimestamp"

    fun export(context: Context, source: File, displayName: String): Uri {
        require(source.exists()) { "源文件不存在" }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            exportViaMediaStore(context, source, displayName)
        } else {
            exportLegacy(context, source, displayName)
        }
    }

    private fun exportViaMediaStore(context: Context, source: File, displayName: String): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, RELATIVE_FOLDER)
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("无法在相册中创建 " + displayName)
        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output, DEFAULT_BUFFER_SIZE * 4) }
            } ?: throw IllegalStateException("无法写入相册文件")
            val finished = ContentValues().apply {
                put(MediaStore.Video.Media.IS_PENDING, 0)
                put(MediaStore.Video.Media.SIZE, source.length())
            }
            resolver.update(uri, finished, null, null)
            return uri
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }

    private fun exportLegacy(context: Context, source: File, displayName: String): Uri {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
            "TeslaTimestamp"
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("无法创建目录 " + directory.absolutePath)
        }
        val target = uniqueFile(directory, displayName)
        source.copyTo(target, overwrite = true)
        MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf("video/mp4"), null)
        return Uri.fromFile(target)
    }

    private fun uniqueFile(directory: File, name: String): File {
        var candidate = File(directory, name)
        if (!candidate.exists()) return candidate
        val stem = name.substringBeforeLast('.')
        val extension = name.substringAfterLast('.', "mp4")
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, stem + "_" + index + "." + extension)
            index++
        }
        return candidate
    }
}
