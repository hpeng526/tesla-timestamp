package com.teslacam.timestamp.data

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Small formatting helpers shared by the UI and the overlay renderer. */
object TimeFormats {

    // Locale.US keeps the digits / pattern identical on every device and on CI (e.g. LANG=C).
    private val DATE_TIME: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss", Locale.US)

    fun dateTime(epochMillis: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        DATE_TIME.format(Instant.ofEpochMilli(epochMillis).atZone(zone))

    fun date(epochMillis: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        dateTime(epochMillis, zone).substring(0, 10)

    fun clock(epochMillis: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        dateTime(epochMillis, zone).substring(11, 19)

    fun fileSize(bytes: Long): String = when {
        bytes <= 0L -> "-"
        bytes < 1024L -> bytes.toString() + " B"
        bytes < 1024L * 1024L -> String.format(Locale.US, "%.0f KB", bytes / 1024.0)
        bytes < 1024L * 1024L * 1024L -> String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
        else -> String.format(Locale.US, "%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
    }

    fun duration(seconds: Long): String {
        val total = seconds.coerceAtLeast(0)
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val secs = total % 60
        return if (hours > 0) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, secs)
        } else {
            String.format(Locale.US, "%02d:%02d", minutes, secs)
        }
    }
}
