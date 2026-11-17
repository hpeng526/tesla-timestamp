package com.teslacam.timestamp.ui

import android.content.Context
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.net.Uri
import android.view.Surface
import android.view.TextureView
import kotlin.math.min

/**
 * Minimal TextureView based player used by the result sheet. A TextureView keeps the video inside
 * the normal view hierarchy (no sideband overlay), so it always shows the burned in timestamp.
 */
class SimpleVideoPlayer(
    private val context: Context,
    private val textureView: TextureView
) : TextureView.SurfaceTextureListener {

    private var player: MediaPlayer? = null
    private var pendingUri: Uri? = null

    var onPrepared: ((MediaPlayer) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    init {
        textureView.surfaceTextureListener = this
    }

    fun play(uri: Uri) {
        pendingUri = uri
        if (textureView.isAvailable) {
            startPlayback(uri)
        }
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        pendingUri?.let { startPlayback(it) }
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        release()
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    private fun startPlayback(uri: Uri) {
        release()
        val mediaPlayer = MediaPlayer()
        player = mediaPlayer
        try {
            mediaPlayer.setDataSource(context, uri)
            mediaPlayer.setSurface(Surface(textureView.surfaceTexture))
            mediaPlayer.isLooping = true
            mediaPlayer.setOnPreparedListener { prepared ->
                applyAspect(prepared.videoWidth, prepared.videoHeight)
                prepared.start()
                onPrepared?.invoke(prepared)
            }
            mediaPlayer.setOnVideoSizeChangedListener { mp, _, _ ->
                applyAspect(mp.videoWidth, mp.videoHeight)
            }
            mediaPlayer.setOnErrorListener { _, what, extra ->
                onError?.invoke("播放失败 (" + what + "/" + extra + ")")
                true
            }
            mediaPlayer.prepareAsync()
        } catch (error: Exception) {
            onError?.invoke(error.message ?: "无法播放")
        }
    }

    private fun applyAspect(videoWidth: Int, videoHeight: Int) {
        if (videoWidth <= 0 || videoHeight <= 0) return
        val viewWidth = textureView.width.toFloat()
        val viewHeight = textureView.height.toFloat()
        if (viewWidth <= 0f || viewHeight <= 0f) return
        val scale = min(viewWidth / videoWidth, viewHeight / videoHeight)
        val matrix = Matrix()
        matrix.setScale(
            scale * videoWidth / viewWidth,
            scale * videoHeight / viewHeight,
            viewWidth / 2f,
            viewHeight / 2f
        )
        textureView.setTransform(matrix)
    }

    fun release() {
        player?.let { mediaPlayer ->
            runCatching { mediaPlayer.stop() }
            runCatching { mediaPlayer.release() }
        }
        player = null
    }
}
