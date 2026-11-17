package com.teslacam.timestamp.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.media.MediaMetadataRetriever
import com.teslacam.timestamp.data.MediaSource
import kotlin.math.max

/**
 * Renders a still preview of a clip exactly the way the encoder will draw the overlay:
 * same text size fraction, same margins, same box opacity and the same position presets.
 */
object PreviewComposer {

    private const val PREVIEW_WIDTH = 720
    private const val PREVIEW_OFFSET_US = 1_000_000L

    fun buildLines(startEpochMillis: Long, style: OverlayStyle, detailText: String?): List<String> {
        val first = OverlayText.firstLine(
            startEpochMillis + PREVIEW_OFFSET_US / 1000L,
            style
        )
        val details = if (style.showDetails) detailText else null
        return if (details.isNullOrBlank()) listOf(first) else listOf(first, details)
    }

    fun compose(
        context: Context,
        source: MediaSource,
        startEpochMillis: Long,
        style: OverlayStyle,
        detailText: String?
    ): Bitmap {
        val frame = loadFrame(context, source) ?: placeholder()
        val scaled = scaleToWidth(frame, PREVIEW_WIDTH)
        if (frame !== scaled) frame.recycle()
        val canvas = Canvas(scaled)
        val lines = buildLines(startEpochMillis, style, detailText)
        val textSizePx = max(10f, scaled.height * style.textFraction)
        val overlay = OverlayBitmapFactory.create(lines, textSizePx, style)
        val margin = max(2, (scaled.height * style.marginFraction).toInt())
        val x = when (style.position) {
            OverlayPosition.TOP_LEFT, OverlayPosition.BOTTOM_LEFT -> margin
            else -> max(margin, scaled.width - margin - overlay.width)
        }
        val y = when (style.position) {
            OverlayPosition.TOP_LEFT, OverlayPosition.TOP_RIGHT -> margin
            else -> max(margin, scaled.height - margin - overlay.height)
        }
        canvas.drawBitmap(overlay, x.toFloat(), y.toFloat(), null)
        overlay.recycle()
        return scaled
    }

    private fun loadFrame(context: Context, source: MediaSource): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            source.attachTo(retriever, context)
            retriever.getFrameAtTime(PREVIEW_OFFSET_US, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0L)
                ?: retriever.frameAtTime
        } catch (error: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun scaleToWidth(bitmap: Bitmap, targetWidth: Int): Bitmap {
        if (bitmap.width <= 0 || bitmap.height <= 0) return bitmap
        val scale = targetWidth.toFloat() / bitmap.width
        val height = max(1, (bitmap.height * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(bitmap, targetWidth, height, true)
        return if (scaled.isMutable && scaled.config == Bitmap.Config.ARGB_8888) {
            scaled
        } else {
            scaled.copy(Bitmap.Config.ARGB_8888, true)
        }
    }

    private fun placeholder(): Bitmap {
        val bitmap = Bitmap.createBitmap(PREVIEW_WIDTH, PREVIEW_WIDTH * 9 / 16, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.parseColor("#171A20"))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 24f
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(
            "无法读取预览画面",
            bitmap.width / 2f,
            bitmap.height / 2f,
            paint
        )
        return bitmap
    }
}
