package com.teslacam.timestamp.data

import android.content.Context
import android.media.MediaExtractor
import android.net.Uri
import java.io.File

/**
 * A readable MP4 file. TeslaCam clips can come from a SAF tree (USB drive, SD card, Documents
 * provider) or from a plain file path (app accessible folder / direct path devices).
 */
sealed class MediaSource {

    abstract val displayName: String
    abstract val key: String

    data class Document(val uri: Uri, override val displayName: String) : MediaSource() {
        override val key: String get() = uri.toString()
    }

    data class LocalFile(val file: File) : MediaSource() {
        override val displayName: String get() = file.name
        override val key: String get() = file.absolutePath
    }

    fun sizeBytes(context: Context): Long = when (this) {
        is Document -> try {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: 0L
        } catch (error: Exception) {
            0L
        }
        is LocalFile -> if (file.exists()) file.length() else 0L
    }

    fun lastModified(context: Context): Long = when (this) {
        is Document -> try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val docMod = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    if (docMod >= 0 && !cursor.isNull(docMod)) {
                        val value = cursor.getLong(docMod)
                        if (value > 0L) return@use value
                    }
                    val dateTaken = cursor.getColumnIndex(android.provider.MediaStore.MediaColumns.DATE_TAKEN)
                    if (dateTaken >= 0 && !cursor.isNull(dateTaken)) {
                        val value = cursor.getLong(dateTaken)
                        if (value > 0L) return@use value
                    }
                    val dateMod = cursor.getColumnIndex(android.provider.MediaStore.MediaColumns.DATE_MODIFIED)
                    if (dateMod >= 0 && !cursor.isNull(dateMod)) {
                        val seconds = cursor.getLong(dateMod)
                        if (seconds > 0L) return@use seconds * 1000L
                    }
                    val dateAdded = cursor.getColumnIndex(android.provider.MediaStore.MediaColumns.DATE_ADDED)
                    if (dateAdded >= 0 && !cursor.isNull(dateAdded)) {
                        val seconds = cursor.getLong(dateAdded)
                        if (seconds > 0L) return@use seconds * 1000L
                    }
                    0L
                } else {
                    0L
                }
            } ?: 0L
        } catch (error: Exception) {
            0L
        }
        is LocalFile -> file.lastModified()
    }

    /** Points a MediaMetadataRetriever at this source (used for the pre-composition preview). */
    fun attachTo(retriever: android.media.MediaMetadataRetriever, context: Context) {
        when (this) {
            is Document -> {
                val descriptor = context.contentResolver.openAssetFileDescriptor(uri, "r")
                    ?: throw IllegalStateException("无法打开文件: " + displayName)
                descriptor.use {
                    retriever.setDataSource(it.fileDescriptor, it.startOffset, it.length)
                }
            }
            is LocalFile -> retriever.setDataSource(file.absolutePath)
        }
    }

    /**
     * Creates a MediaExtractor that reads this source. The caller owns the returned extractor and
     * must release it. The framework duplicates the file descriptor used here.
     */
    fun openExtractor(context: Context): MediaExtractor {
        val extractor = MediaExtractor()
        try {
            when (this) {
                is Document -> {
                    val descriptor = context.contentResolver.openAssetFileDescriptor(uri, "r")
                        ?: throw IllegalStateException("无法打开文件: " + displayName)
                    descriptor.use {
                        extractor.setDataSource(it.fileDescriptor, it.startOffset, it.length)
                    }
                }
                is LocalFile -> extractor.setDataSource(file.absolutePath)
            }
        } catch (error: Exception) {
            extractor.release()
            throw error
        }
        return extractor
    }
}
