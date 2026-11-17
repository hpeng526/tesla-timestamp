package com.teslacam.timestamp.ui

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.widget.ImageView
import com.teslacam.timestamp.data.MediaSource
import java.util.concurrent.Executors

/**
 * Loads the first frame of a clip off the main thread and keeps a small memory cache so scrolling
 * the clip list stays smooth.
 */
class ThumbnailLoader(private val context: Context) {

    private val cache = LruCache<String, Bitmap>(32)
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    fun load(source: MediaSource, imageView: ImageView) {
        val key = "thumb:" + source.key
        val cached = cache.get(key)
        if (cached != null) {
            imageView.tag = key
            imageView.alpha = 1f
            imageView.setImageBitmap(cached)
            return
        }
        imageView.tag = key
        imageView.setImageDrawable(null)
        imageView.alpha = 0f
        executor.execute {
            val bitmap = runCatching { frameOf(source) }.getOrNull() ?: return@execute
            cache.put(key, bitmap)
            mainHandler.post {
                if (imageView.tag == key) {
                    imageView.setImageBitmap(bitmap)
                    imageView.animate().alpha(1f).setDuration(160L).start()
                }
            }
        }
    }

    fun shutdown() {
        executor.shutdownNow()
        cache.evictAll()
    }

    private fun frameOf(source: MediaSource): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            source.attachTo(retriever, context)
            retriever.getFrameAtTime(1_000_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0L)
        } catch (error: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }
}
