package com.teslacam.timestamp

import com.teslacam.timestamp.data.TeslaNaming
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class TeslaNamingTest {

    private val zone: ZoneId = ZoneId.of("Asia/Shanghai")

    @Test
    fun parsesRecentClipTimestamp() {
        val expected = Instant.parse("2024-05-01T04:30:00Z").toEpochMilli()
        assertEquals(expected, TeslaNaming.parseTimestamp("2024-05-01_12-30-00-front.mp4", zone))
    }

    @Test
    fun cameraNameIsExtractedFromFileName() {
        assertEquals("front", TeslaNaming.cameraOf("2024-05-01_12-30-00-front.mp4"))
        assertEquals("left_repeater", TeslaNaming.cameraOf("2024-05-01_12-30-00-left_repeater.mp4"))
    }

    @Test
    fun cameraNameIsExtractedFromEventFile() {
        assertEquals("back", TeslaNaming.cameraOf("back.mp4"))
        assertEquals("right_pillar", TeslaNaming.cameraOf("right_pillar.mp4"))
    }

    @Test
    fun unknownFilesHaveNoCamera() {
        assertNull(TeslaNaming.cameraOf("notes.txt"))
    }

    @Test
    fun clipDirectoryIsRecognised() {
        assertEquals(
            Instant.parse("2024-05-01T04:30:00Z").toEpochMilli(),
            TeslaNaming.parseClipDirectory("2024-05-01_12-30-00", zone)
        )
        assertFalse(TeslaNaming.isClipDirectoryName("2024-05-01"))
        assertNull(TeslaNaming.parseClipDirectory("RecentClips", zone))
    }

    @Test
    fun cameraLabelsAreFriendly() {
        assertEquals("前视", TeslaNaming.cameraLabel("front"))
        assertEquals("左后", TeslaNaming.cameraLabel("left_repeater"))
    }

    @Test
    fun legacyNameWithoutCameraStillParses() {
        assertEquals(
            Instant.parse("2024-05-01T04:30:00Z").toEpochMilli(),
            TeslaNaming.parseTimestamp("2024-05-01_12-30-00.mp4", zone)
        )
    }

    @Test
    fun invalidTimestampsReturnNull() {
        assertNull(TeslaNaming.parseTimestamp("movie.mp4", zone))
        assertNull(TeslaNaming.parseTimestamp("2024-13-45_99-99-99-front.mp4", zone))
    }
}
