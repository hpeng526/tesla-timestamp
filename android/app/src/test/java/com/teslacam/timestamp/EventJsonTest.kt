package com.teslacam.timestamp

import com.teslacam.timestamp.data.TeslaEventInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EventJsonTest {

    private val sample = """
        {
          "timestamp": "2024-05-01T04:30:00",
          "city": "上海市",
          "est_lat": "31.2304",
          "est_lon": "121.4737",
          "reason": "sentry_aware_object_detection",
          "camera": "0"
        }
    """.trimIndent()

    @Test
    fun parsesKnownFields() {
        val info = TeslaEventInfo.parse(sample)
        assertEquals("2024-05-01T04:30:00", info.timestampIso)
        assertEquals("上海市", info.city)
        assertEquals(31.2304, info.estLat ?: 0.0, 0.00001)
        assertEquals(121.4737, info.estLon ?: 0.0, 0.00001)
        assertEquals("哨兵事件", info.reasonLabel())
    }

    @Test
    fun buildsReferenceLine() {
        val line = TeslaEventInfo.parse(sample).referenceLine()
        assertNotNull(line)
        val text = line ?: ""
        assertTrue(text.contains("上海市"))
        assertTrue(text.contains("31.23040"))
    }

    @Test
    fun handlesMissingFields() {
        val info = TeslaEventInfo.parse("{}")
        assertNull(info.timestampIso)
        assertNull(info.city)
        assertNull(info.estLat)
        assertNull(info.referenceLine())
    }

    @Test
    fun handlesNumericCoordinates() {
        val info = TeslaEventInfo.parse("{\"est_lat\": -33.86, \"est_lon\": 151.21}")
        assertEquals(-33.86, info.estLat ?: 0.0, 0.00001)
        assertEquals(151.21, info.estLon ?: 0.0, 0.00001)
    }

    @Test
    fun mapsUserInteractionReason() {
        val info = TeslaEventInfo.parse("{\"reason\": \"user_interaction_honk\"}")
        assertEquals("鸣笛保存", info.reasonLabel())
    }
}
