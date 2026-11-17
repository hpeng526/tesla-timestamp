package com.teslacam.timestamp.data

import java.util.Locale

/**
 * Minimal reader for the event.json file Tesla writes inside SavedClips / SentryClips folders.
 * The file is small and flat, so a dependency free field extractor keeps this class usable in
 * plain JVM unit tests (org.json is not available there).
 */
data class TeslaEventInfo(
    val timestampIso: String? = null,
    val city: String? = null,
    val estLat: Double? = null,
    val estLon: Double? = null,
    val reason: String? = null,
    val camera: String? = null
) {
    fun referenceLine(): String? {
        val parts = mutableListOf<String>()
        reasonLabel()?.let { parts += it }
        city?.takeIf { it.isNotBlank() }?.let { parts += it }
        val lat = estLat
        val lon = estLon
        if (lat != null && lon != null) {
            parts += String.format(Locale.US, "%.5f, %.5f", lat, lon)
        }
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    fun reasonLabel(): String? = when (reason?.lowercase()) {
        null, "" -> null
        "sentry_aware_object_detection" -> "哨兵事件"
        "user_interaction_dashcam_icon_tapped" -> "手动保存"
        "user_interaction_dashcam_panel_save" -> "手动保存"
        "user_interaction_dashcam_launcher_action_tapped" -> "手动保存"
        "user_interaction_honk" -> "鸣笛保存"
        "sentry_aware_accel_v2" -> "碰撞事件"
        "saved_clip" -> "已保存"
        else -> reason
    }

    companion object {
        private const val WS = """[ \t\r\n]*"""
        private const val QUOTE = """["]"""

        fun parse(raw: String): TeslaEventInfo {
            return TeslaEventInfo(
                timestampIso = stringField(raw, "timestamp"),
                city = stringField(raw, "city"),
                estLat = doubleField(raw, "est_lat"),
                estLon = doubleField(raw, "est_lon"),
                reason = stringField(raw, "reason"),
                camera = stringField(raw, "camera")
            )
        }

        private fun stringField(raw: String, name: String): String? {
            val pattern = Regex(QUOTE + Regex.escape(name) + QUOTE + WS + ":" + WS +
                QUOTE + "([^\"]*)" + QUOTE)
            val match = pattern.find(raw) ?: return null
            return match.groupValues[1].takeIf { it.isNotBlank() && it != "null" }
        }

        private fun doubleField(raw: String, name: String): Double? {
            // Tesla writes coordinates either as JSON numbers or as quoted strings.
            val pattern = Regex(QUOTE + Regex.escape(name) + QUOTE + WS + ":" + WS +
                QUOTE + "?(-?[0-9]+(?:\\.[0-9]+)?)" + QUOTE + "?")
            val match = pattern.find(raw) ?: return null
            return match.groupValues[1].toDoubleOrNull()
        }
    }
}
