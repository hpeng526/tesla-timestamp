package com.teslacam.timestamp.data

import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Pure helpers that understand the naming convention used by Tesla dashcam clips.
 *
 * Tesla writes every camera into its own MP4 file:
 *  - RecentClips: "2024-05-01_12-30-00-front.mp4"
 *  - SavedClips / SentryClips: "<clip dir>/front.mp4" where the directory is "2024-05-01_12-30-00".
 *
 * The timestamp inside the name is the local wall clock time of the car, therefore it is converted
 * with the device time zone - the same assumption the desktop reference script makes.
 */
object TeslaNaming {

    private val TIMESTAMP_IN_NAME_REGEX =
        Regex("""([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})""")

    private val CLIP_DIR_REGEX =
        Regex("""^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$""")

    private val CAMERA_FILE_REGEX =
        Regex("""^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}-(.+)\.mp4$""", RegexOption.IGNORE_CASE)

    private val PLAIN_MP4_REGEX = Regex("""^(.+)\.mp4$""", RegexOption.IGNORE_CASE)

    fun isMp4(fileName: String): Boolean = fileName.endsWith(".mp4", ignoreCase = true)

    fun baseName(fileName: String): String = if (isMp4(fileName)) fileName.dropLast(4) else fileName

    fun isClipDirectoryName(name: String): Boolean = CLIP_DIR_REGEX.matches(name)

    /** Parses "2024-05-01_12-30-00" (optionally followed by more text) into epoch millis. */
    fun parseTimestamp(name: String, zone: ZoneId = ZoneId.systemDefault()): Long? {
        val match = TIMESTAMP_IN_NAME_REGEX.find(baseName(name)) ?: return null
        return toEpochMillis(match.groupValues, zone)
    }

    /** Epoch millis of a clip directory name, or null when it is not a Tesla clip directory. */
    fun parseClipDirectory(name: String, zone: ZoneId = ZoneId.systemDefault()): Long? {
        if (!isClipDirectoryName(name)) return null
        val match = TIMESTAMP_IN_NAME_REGEX.find(name) ?: return null
        return toEpochMillis(match.groupValues, zone)
    }

    /**
     * Camera identifier for a clip file: "2024-05-01_12-30-00-left_repeater.mp4" -> "left_repeater",
     * "front.mp4" -> "front". Returns null when no camera can be derived.
     */
    fun cameraOf(fileName: String): String? {
        CAMERA_FILE_REGEX.find(fileName)?.let { return it.groupValues[1].lowercase() }
        PLAIN_MP4_REGEX.find(fileName)?.let { return it.groupValues[1].lowercase() }
        return null
    }

    /** Chinese label for a Tesla camera identifier. */
    fun cameraLabel(camera: String?): String = when (camera?.lowercase()) {
        null, "" -> "视频"
        "front" -> "前视"
        "back" -> "后视"
        "left_repeater" -> "左后"
        "right_repeater" -> "右后"
        "left_pillar" -> "左柱"
        "right_pillar" -> "右柱"
        else -> camera
    }

    private fun toEpochMillis(groups: List<String>, zone: ZoneId): Long? {
        if (groups.size < 7) return null
        return try {
            LocalDateTime.of(
                groups[1].toInt(),
                groups[2].toInt(),
                groups[3].toInt(),
                groups[4].toInt(),
                groups[5].toInt(),
                groups[6].toInt()
            ).atZone(zone).toInstant().toEpochMilli()
        } catch (error: Exception) {
            null
        }
    }
}
