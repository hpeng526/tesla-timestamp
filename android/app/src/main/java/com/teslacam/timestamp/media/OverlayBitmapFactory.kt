package com.teslacam.timestamp.media

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import kotlin.math.ceil
import kotlin.math.max

/**
 * Renders the timestamp into an ARGB bitmap the same way the reference ffmpeg filter does:
 * white text on a semi transparent black box (box=1:boxcolor=black@0.5, fontcolor=white).
 */
object OverlayBitmapFactory {

    fun create(lines: List<String>, textSizePx: Float, style: OverlayStyle): Bitmap {
        val safeLines = if (lines.isEmpty()) listOf("") else lines
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            this.textSize = textSizePx
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            isSubpixelText = true
        }
        val padding = max(2, (textSizePx * 0.30f).toInt())
        val lineHeight = paint.descent() - paint.ascent()
        val lineSpacing = max(1f, textSizePx * 0.10f)

        var textWidth = 0f
        safeLines.forEach { line -> textWidth = max(textWidth, paint.measureText(line)) }

        val width = max(1, ceil(textWidth).toInt() + padding * 2)
        val height = max(1, ceil(lineHeight * safeLines.size + lineSpacing * (safeLines.size - 1)).toInt() + padding * 2)

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setHasAlpha(true)
        val canvas = Canvas(bitmap)
        val boxPaint = Paint().apply {
            color = Color.BLACK
            alpha = (255 * style.boxAlpha.coerceIn(0f, 1f)).toInt()
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), boxPaint)
        safeLines.forEachIndexed { index, line ->
            val baseline = padding - paint.ascent() + index * (lineHeight + lineSpacing)
            canvas.drawText(line, padding.toFloat(), baseline, paint)
        }
        return bitmap
    }
}
