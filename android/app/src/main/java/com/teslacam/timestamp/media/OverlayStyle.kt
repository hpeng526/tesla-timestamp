package com.teslacam.timestamp.media

import com.teslacam.timestamp.data.TeslaEventInfo
import com.teslacam.timestamp.data.TimeFormats
import java.time.ZoneId

enum class OverlayPosition(val label: String) {
    TOP_LEFT("左上"),
    TOP_RIGHT("右上"),
    BOTTOM_LEFT("左下"),
    BOTTOM_RIGHT("右下")
}

/**
 * How the burned in timestamp looks. Sizes are fractions of the video height so the result looks
 * identical at every resolution, mirroring the reference script (fontsize 50 at 1080p is about 5%).
 */
data class OverlayStyle(
    val position: OverlayPosition = OverlayPosition.TOP_LEFT,
    val textScale: Float = 1f,
    val showDate: Boolean = true,
    val showDetails: Boolean = false,
    val boxAlpha: Float = 0.5f,
    val marginFraction: Float = 0.02f
) {
    val textFraction: Float get() = BASE_TEXT_FRACTION * textScale

    companion object {
        const val BASE_TEXT_FRACTION = 0.055f
        val SIZE_PRESETS = listOf(0.7f, 1f, 1.4f)
        val SIZE_LABELS = listOf("小", "中", "大")
    }
}

/** Formats the overlay lines for a given frame wall clock time. */
object OverlayText {

    fun timeLine(epochMillis: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        TimeFormats.dateTime(epochMillis, zone)

    fun firstLine(
        epochMillis: Long,
        style: OverlayStyle,
        zone: ZoneId = ZoneId.systemDefault()
    ): String = if (style.showDate) {
        TimeFormats.dateTime(epochMillis, zone)
    } else {
        TimeFormats.clock(epochMillis, zone)
    }

    /**
     * Optional second line with camera / event metadata, similar to the location line the reference
     * Windows script prepares from event.json.
     */
    fun detailLine(
        cameraLabel: String?,
        eventInfo: TeslaEventInfo?
    ): String? {
        val parts = mutableListOf<String>()
        cameraLabel?.takeIf { it.isNotBlank() }?.let { parts += it }
        eventInfo?.city?.takeIf { it.isNotBlank() }?.let { parts += it }
        val lat = eventInfo?.estLat
        val lon = eventInfo?.estLon
        if (lat != null && lon != null) {
            parts += String.format(java.util.Locale.US, "%.5f, %.5f", lat, lon)
        }
        eventInfo?.reasonLabel()?.let { parts += it }
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }
}
