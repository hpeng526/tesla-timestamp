package com.teslacam.timestamp

import com.teslacam.timestamp.data.TeslaEventInfo
import com.teslacam.timestamp.media.OverlayStyle
import com.teslacam.timestamp.media.OverlayText
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OverlayStyleTest {

    private val epoch = Instant.parse("2024-05-01T04:30:05Z").toEpochMilli()

    @Test
    fun formatsFullTimestamp() {
        assertEquals("2024-05-01 12:30:05", OverlayText.timeLine(epoch))
    }

    @Test
    fun clockOnlyWhenDateIsHidden() {
        val style = OverlayStyle(showDate = false)
        assertEquals("12:30:05", OverlayText.firstLine(epoch, style))
    }

    @Test
    fun textSizeScalesWithVideoHeight() {
        val medium = OverlayStyle(textScale = 1f)
        val small = OverlayStyle(textScale = 0.7f)
        assertEquals(1080 * 0.055f, 1080 * medium.textFraction, 0.001f)
        assertTrue(medium.textFraction > small.textFraction)
    }

    @Test
    fun detailLineContainsCameraAndCity() {
        val info = TeslaEventInfo(estLat = 31.2304, estLon = 121.4737, city = "上海市")
        val line = OverlayText.detailLine("前视", info)
        requireNotNull(line)
        assertTrue(line.contains("前视"))
        assertTrue(line.contains("上海市"))
        assertTrue(line.contains("31.23040"))
    }

    @Test
    fun detailLineWithoutMetadata() {
        assertNull(OverlayText.detailLine(null, null))
        assertEquals("前视", OverlayText.detailLine("前视", null))
    }
}
