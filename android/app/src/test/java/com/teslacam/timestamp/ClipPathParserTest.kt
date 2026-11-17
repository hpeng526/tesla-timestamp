package com.teslacam.timestamp

import com.teslacam.timestamp.data.ClipCategory
import com.teslacam.timestamp.data.ClipPathParser
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ClipPathParserTest {

    private val zone: ZoneId = ZoneId.of("Asia/Shanghai")
    private val fiveAm = Instant.parse("2024-05-01T04:30:00Z").toEpochMilli()

    @Test
    fun parsesRecentClipsFile() {
        val identity = ClipPathParser.parse("TeslaCam/RecentClips/2024-05-01_12-30-00-front.mp4", zone)
        requireNotNull(identity)
        assertEquals(ClipCategory.RECENT, identity.category)
        assertEquals("front", identity.camera)
        assertEquals(fiveAm, identity.clipStartMillis)
        assertTrue(identity.timestampFromName)
    }

    @Test
    fun parsesSavedClipsDirectoryLayout() {
        val identity = ClipPathParser.parse("TeslaCam/SavedClips/2024-05-01_12-30-00/back.mp4", zone)
        requireNotNull(identity)
        assertEquals(ClipCategory.SAVED, identity.category)
        assertEquals("back", identity.camera)
        assertEquals(fiveAm, identity.clipStartMillis)
    }

    @Test
    fun parsesSentryClipsDirectoryLayout() {
        val identity = ClipPathParser.parse("TeslaCam/SentryClips/2024-05-01_12-30-00/left_repeater.mp4", zone)
        requireNotNull(identity)
        assertEquals(ClipCategory.SENTRY, identity.category)
        assertEquals("left_repeater", identity.camera)
    }

    @Test
    fun ignoresEventJson() {
        assertNull(ClipPathParser.parse("TeslaCam/SentryClips/2024-05-01_12-30-00/event.json", zone))
    }

    @Test
    fun ignoresFilesWithoutTimestamp() {
        assertNull(ClipPathParser.parse("Download/movie.mp4", zone))
    }

    @Test
    fun sameClipGroupForDifferentCameras() {
        val front = ClipPathParser.parse("TeslaCam/SavedClips/2024-05-01_12-30-00/front.mp4", zone)
        val back = ClipPathParser.parse("TeslaCam/SavedClips/2024-05-01_12-30-00/back.mp4", zone)
        requireNotNull(front)
        requireNotNull(back)
        assertEquals(front.groupId, back.groupId)
        assertNotEquals(front.camera, back.camera)
    }

    @Test
    fun differentMinutesAreDifferentGroups() {
        val first = ClipPathParser.parse("TeslaCam/RecentClips/2024-05-01_12-30-00-front.mp4", zone)
        val second = ClipPathParser.parse("TeslaCam/RecentClips/2024-05-01_12-31-00-front.mp4", zone)
        requireNotNull(first)
        requireNotNull(second)
        assertNotEquals(first.groupId, second.groupId)
    }

    @Test
    fun handlesWindowsSeparatorsAndLeadingSlash() {
        val identity = ClipPathParser.parse("\\TeslaCam\\RecentClips\\2024-05-01_12-30-00-back.mp4", zone)
        requireNotNull(identity)
        assertEquals("back", identity.camera)
    }

    @Test
    fun unknownCategoryWhenNoTeslaCamFolder() {
        val identity = ClipPathParser.parse("2024-05-01_12-30-00-front.mp4", zone)
        requireNotNull(identity)
        assertEquals(ClipCategory.RECENT, identity.category)
    }
}
