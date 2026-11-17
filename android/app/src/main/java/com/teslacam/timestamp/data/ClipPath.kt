package com.teslacam.timestamp.data

import java.time.ZoneId

enum class ClipCategory(val label: String) {
    RECENT("近期片段"),
    SAVED("已保存"),
    SENTRY("哨兵模式"),
    UNKNOWN("其他"),
}

/** Everything needed to place a single MP4 file inside the TeslaCam folder tree. */
data class ClipIdentity(
    val category: ClipCategory,
    val clipStartMillis: Long,
    val camera: String?,
    val timestampFromName: Boolean
) {
    val groupId: String get() = category.name + "@" + clipStartMillis
}

/**
 * Turns a path relative to a TeslaCam root (or any folder) into a [ClipIdentity].
 *
 * Supported layouts, all relative paths:
 *  - TeslaCam/RecentClips/2024-05-01_12-30-00-front.mp4
 *  - TeslaCam/SavedClips/2024-05-01_12-30-00/front.mp4
 *  - TeslaCam/SentryClips/2024-05-01_12-30-00/event.json  (not an mp4 -> null)
 *  - anything else that still carries a Tesla timestamp in the file name
 */
object ClipPathParser {

    private val CATEGORY_NAMES = mapOf(
        "recentclips" to ClipCategory.RECENT,
        "savedclips" to ClipCategory.SAVED,
        "sentryclips" to ClipCategory.SENTRY
    )

    fun parse(relativePath: String, zone: ZoneId = ZoneId.systemDefault()): ClipIdentity? {
        val path = relativePath.replace('\\', '/').trim('/')
        if (path.isEmpty()) return null
        val segments = path.split('/').filter { it.isNotEmpty() }
        if (segments.isEmpty()) return null
        val fileName = segments.last()
        if (!TeslaNaming.isMp4(fileName)) return null

        val directorySegments = segments.dropLast(1)
        var category = ClipCategory.UNKNOWN
        directorySegments.forEach { segment ->
            CATEGORY_NAMES[segment.lowercase()]?.let { category = it }
        }

        // 1) Event clips: the parent directory carries the start time.
        for (index in directorySegments.indices.reversed()) {
            val start = TeslaNaming.parseClipDirectory(directorySegments[index], zone) ?: continue
            return ClipIdentity(
                category = if (category == ClipCategory.UNKNOWN) ClipCategory.SAVED else category,
                clipStartMillis = start,
                camera = TeslaNaming.cameraOf(fileName) ?: TeslaNaming.baseName(fileName).lowercase(),
                timestampFromName = true
            )
        }

        // 2) Recent clips: the file itself carries the start time.
        val start = TeslaNaming.parseTimestamp(fileName, zone) ?: return null
        return ClipIdentity(
            category = if (category == ClipCategory.UNKNOWN) ClipCategory.RECENT else category,
            clipStartMillis = start,
            camera = TeslaNaming.cameraOf(fileName),
            timestampFromName = true
        )
    }
}
