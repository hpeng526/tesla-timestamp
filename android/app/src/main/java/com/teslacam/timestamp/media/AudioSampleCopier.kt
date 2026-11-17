package com.teslacam.timestamp.media

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.nio.ByteBuffer
import kotlin.math.max

/**
 * Copies the compressed audio track of the source into the muxer without re-encoding it.
 * Samples are interleaved with the video by only writing audio up to the newest video timestamp,
 * which keeps memory usage flat even for long clips.
 */
internal class AudioSampleCopier(
    private val extractor: MediaExtractor,
    val format: MediaFormat
) {
    private val buffer: ByteBuffer
    private var pending: ByteArray? = null
    private var pendingPtsUs = 0L
    private var muxer: MediaMuxer? = null
    private var trackIndex = -1
    private var finished = false
    private val info = MediaCodec.BufferInfo()

    init {
        val maxInputSize = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
        } else {
            0
        }
        buffer = ByteBuffer.allocateDirect(max(64 * 1024, maxInputSize))
    }

    fun attachToMuxer(target: MediaMuxer) {
        trackIndex = target.addTrack(format)
        muxer = target
    }

    fun pumpUpTo(limitPtsUs: Long) {
        val target = muxer ?: return
        if (finished || trackIndex < 0) return
        while (true) {
            val held = pending
            if (held != null) {
                if (pendingPtsUs > limitPtsUs) return
                writeSample(target, held, pendingPtsUs)
                pending = null
                continue
            }
            buffer.clear()
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) {
                finished = true
                return
            }
            val ptsUs = extractor.sampleTime
            if (ptsUs > limitPtsUs) {
                val copy = ByteArray(size)
                buffer.position(0)
                buffer.limit(size)
                buffer.get(copy)
                pending = copy
                pendingPtsUs = ptsUs
                extractor.advance()
                return
            }
            buffer.position(0)
            buffer.limit(size)
            writeSample(target, size, ptsUs)
            extractor.advance()
        }
    }

    fun flushAll() {
        val target = muxer ?: return
        if (trackIndex < 0) return
        while (!finished) {
            val held = pending
            if (held != null) {
                writeSample(target, held, pendingPtsUs)
                pending = null
                continue
            }
            buffer.clear()
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) {
                finished = true
                return
            }
            buffer.position(0)
            buffer.limit(size)
            writeSample(target, size, extractor.sampleTime)
            extractor.advance()
        }
    }

    private fun writeSample(target: MediaMuxer, bytes: ByteArray, ptsUs: Long) {
        buffer.clear()
        buffer.put(bytes)
        buffer.position(0)
        buffer.limit(bytes.size)
        info.set(0, bytes.size, ptsUs, MediaCodec.BUFFER_FLAG_KEY_FRAME)
        target.writeSampleData(trackIndex, buffer, info)
    }

    private fun writeSample(target: MediaMuxer, size: Int, ptsUs: Long) {
        info.set(0, size, ptsUs, MediaCodec.BUFFER_FLAG_KEY_FRAME)
        target.writeSampleData(trackIndex, buffer, info)
    }
}
