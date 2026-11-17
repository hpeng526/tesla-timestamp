package com.teslacam.timestamp.data

/** One MP4 inside a clip group (front / back / left_repeater ...). */
data class ClipFile(
    val id: String,
    val camera: String?,
    val source: MediaSource,
    val sizeBytes: Long
) {
    val displayName: String get() = source.displayName
}

/**
 * All camera files that belong to one Tesla minute. RecentClips groups hold one file per camera,
 * SavedClips / SentryClips groups hold up to four (plus event.json metadata).
 */
data class ClipGroup(
    val id: String,
    val category: ClipCategory,
    val startEpochMillis: Long,
    val eventInfo: TeslaEventInfo?,
    val files: List<ClipFile>
) {
    val title: String get() = TimeFormats.dateTime(startEpochMillis)

    val subtitle: String
        get() {
            val parts = mutableListOf<String>()
            parts += category.label
            parts += files.size.toString() + " 个视频"
            eventInfo?.reasonLabel()?.let { parts += it }
            return parts.joinToString(" · ")
        }
}
