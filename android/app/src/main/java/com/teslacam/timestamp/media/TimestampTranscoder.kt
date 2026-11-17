package com.teslacam.timestamp.media

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.view.Surface
import com.teslacam.timestamp.data.MediaSource
import java.io.File

private const val MIME_VIDEO_AVC = "video/avc"
private const val DEQUEUE_TIMEOUT_US = 10_000L
private const val TAG = "TimestampTranscoder"

class TranscodeException(message: String, cause: Throwable? = null) : Exception(message, cause)

class TranscodeCancelledException : Exception("已取消")

data class TranscodeRequest(
    val source: MediaSource,
    val outputFile: File,
    val startEpochMillis: Long,
    val style: OverlayStyle,
    val detailText: String?
)

data class TranscodeResult(
    val outputFile: File,
    val width: Int,
    val height: Int,
    val durationMs: Long,
    val frameCount: Long
)

/**
 * Burns a running timestamp into a Tesla dashcam clip.
 *
 * The media pipeline is fully hardware accelerated and needs no external binaries:
 *   MediaExtractor -> MediaCodec decoder -> SurfaceTexture -> GL (video + timestamp overlay)
 *   -> MediaCodec encoder input Surface -> MediaMuxer (audio track copied without re-encoding).
 */
internal class TimestampTranscoder(
    private val context: Context,
    private val request: TranscodeRequest
) {
    @Volatile
    private var cancelled = false

    fun cancel() {
        cancelled = true
    }

    fun transcode(onProgress: (Float) -> Unit): TranscodeResult {
        val style = request.style
        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var renderer: GlTimestampRenderer? = null
        var muxer: MediaMuxer? = null
        var sink: EncoderSink? = null
        var outputWidth = 0
        var outputHeight = 0
        var durationUs = 0L

        try {
            val extractor = try {
                request.source.openExtractor(context)
            } catch (error: Exception) {
                throw TranscodeException("无法读取视频文件: " + request.source.displayName, error)
            }
            videoExtractor = extractor

            val videoTrack = findTrack(extractor, "video/")
                ?: throw TranscodeException("文件中没有视频轨道")
            val videoFormat = extractor.getTrackFormat(videoTrack)
            val mime = videoFormat.getString(MediaFormat.KEY_MIME)
                ?: throw TranscodeException("无法识别视频编码")
            val sourceWidth = videoFormat.getInteger(MediaFormat.KEY_WIDTH)
            val sourceHeight = videoFormat.getInteger(MediaFormat.KEY_HEIGHT)
            if (sourceWidth <= 0 || sourceHeight <= 0) {
                throw TranscodeException("视频尺寸无效")
            }
            durationUs = if (videoFormat.containsKey(MediaFormat.KEY_DURATION)) {
                videoFormat.getLong(MediaFormat.KEY_DURATION)
            } else {
                0L
            }
            if (durationUs <= 0L) durationUs = 1_000_000L
            val rotation = if (videoFormat.containsKey("rotation-degrees")) {
                videoFormat.getInteger("rotation-degrees")
            } else {
                0
            }
            val declaredFrameRate = if (videoFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            } else {
                30
            }
            val frameRate = declaredFrameRate.coerceIn(15, 60)
            val swapDimensions = rotation == 90 || rotation == 270
            val baseWidth = if (swapDimensions) sourceHeight else sourceWidth
            val baseHeight = if (swapDimensions) sourceWidth else sourceHeight

            // ---- encoder (falls back to a supported size when the source is too large) ----
            val encoderChoice = createEncoder(baseWidth, baseHeight, frameRate)
            val enc = encoderChoice.codec
            encoder = enc
            outputWidth = encoderChoice.width
            outputHeight = encoderChoice.height
            android.util.Log.i(
                TAG,
                "encode " + outputWidth + "x" + outputHeight + " @" + frameRate +
                    "fps from " + sourceWidth + "x" + sourceHeight
            )
            val encoderInputSurface = encoderChoice.inputSurface

            // ---- GL renderer (video blit + timestamp overlay) ----
            val gl = try {
                GlTimestampRenderer(outputWidth, outputHeight, rotation)
            } catch (error: Exception) {
                throw TranscodeException("GPU 渲染初始化失败: " + (error.message ?: ""), error)
            }
            renderer = gl
            gl.surfaceTexture.setDefaultBufferSize(sourceWidth, sourceHeight)
            try {
                gl.createEncoderSurface(encoderInputSurface)
            } catch (error: Exception) {
                throw TranscodeException("GPU 渲染初始化失败: " + (error.message ?: ""), error)
            }

            // ---- audio (copied, never re-encoded) ----
            var audioCopier: AudioSampleCopier? = null
            val audioTrack = findTrack(extractor, "audio/")
            if (audioTrack >= 0) {
                val audioFormat = extractor.getTrackFormat(audioTrack)
                val audioSource = try {
                    request.source.openExtractor(context)
                } catch (error: Exception) {
                    null
                }
                if (audioSource != null) {
                    audioExtractor = audioSource
                    val sourceAudioTrack = findTrack(audioSource, "audio/")
                    if (sourceAudioTrack >= 0) {
                        audioSource.selectTrack(sourceAudioTrack)
                        audioCopier = AudioSampleCopier(audioSource, audioFormat)
                    }
                }
            }

            // ---- muxer ----
            val mux = try {
                MediaMuxer(request.outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            } catch (error: Exception) {
                throw TranscodeException("无法创建输出文件", error)
            }
            muxer = mux
            if (rotation != 0 && !swapDimensions) {
                mux.setOrientationHint(rotation)
            }
            val drainSink = EncoderSink(enc, mux, audioCopier)
            sink = drainSink

            // ---- decoder ----
            if (!decoderSupports(mime, sourceWidth, sourceHeight)) {
                throw TranscodeException(
                    "当前手机的解码器不支持 " + sourceWidth + "x" + sourceHeight + " 的视频"
                )
            }
            val dec = try {
                MediaCodec.createDecoderByType(mime)
            } catch (error: Exception) {
                throw TranscodeException("当前设备没有 " + mime + " 解码器", error)
            }
            decoder = dec
            try {
                dec.configure(videoFormat, gl.videoSurface, null, 0)
            } catch (error: Exception) {
                throw TranscodeException(
                    "视频解码器初始化失败 (" + mime + "，" + sourceWidth + "x" + sourceHeight + ")",
                    error
                )
            }
            dec.start()
            extractor.selectTrack(videoTrack)

            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var frameCount = 0L
            var idleLoops = 0

            while (!outputDone) {
                if (cancelled) throw TranscodeCancelledException()

                if (!inputDone) {
                    val inputIndex = dec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuffer = dec.getInputBuffer(inputIndex)
                        if (inputBuffer == null) {
                            dec.queueInputBuffer(inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                dec.queueInputBuffer(inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                dec.queueInputBuffer(inputIndex, 0, sampleSize, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                val outputIndex = dec.dequeueOutputBuffer(bufferInfo, DEQUEUE_TIMEOUT_US)
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> idleLoops = 0
                    outputIndex >= 0 -> {
                        idleLoops = 0
                        val endOfStream =
                            (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        if (bufferInfo.size > 0 && !endOfStream) {
                            dec.releaseOutputBuffer(outputIndex, true)
                            val presentationTimeNs = gl.awaitNewFrame()
                            val ptsUs = presentationTimeNs / 1000L
                            val wallClockMs = request.startEpochMillis + ptsUs / 1000L
                            gl.drawFrame(buildOverlayLines(wallClockMs, style), style)
                            gl.presentFrame(presentationTimeNs)
                            frameCount++
                            val fraction = (ptsUs.toFloat() / durationUs.toFloat()).coerceIn(0f, 0.99f)
                            onProgress(fraction)
                        } else {
                            dec.releaseOutputBuffer(outputIndex, false)
                        }
                        if (endOfStream) outputDone = true
                        drainSink.drain(false)
                    }
                    else -> {
                        idleLoops++
                        if (idleLoops > 20_000) throw TranscodeException("解码超时")
                    }
                }
            }

            if (cancelled) throw TranscodeCancelledException()
            enc.signalEndOfInputStream()
            drainSink.drain(true)
            drainSink.finishAudio()
            if (!drainSink.muxerStarted || frameCount == 0L) {
                throw TranscodeException("没有产生任何视频帧")
            }
            onProgress(1f)
            return TranscodeResult(
                outputFile = request.outputFile,
                width = outputWidth,
                height = outputHeight,
                durationMs = durationUs / 1000L,
                frameCount = frameCount
            )
        } finally {
            runCatching { decoder?.stop() }
            runCatching { decoder?.release() }
            runCatching { renderer?.release() }
            runCatching { encoder?.stop() }
            runCatching { encoder?.release() }
            if (sink?.muxerStarted == true) {
                runCatching { muxer?.stop() }
            }
            runCatching { muxer?.release() }
            runCatching { videoExtractor?.release() }
            runCatching { audioExtractor?.release() }
        }
    }

    private fun buildOverlayLines(wallClockMs: Long, style: OverlayStyle): List<String> {
        val firstLine = OverlayText.firstLine(wallClockMs, style)
        val details = if (style.showDetails) request.detailText else null
        return if (details.isNullOrBlank()) listOf(firstLine) else listOf(firstLine, details)
    }

    private fun findTrack(extractor: MediaExtractor, mimePrefix: String): Int {
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(mimePrefix)) return index
        }
        return -1
    }

    private class EncoderChoice(
        val codec: MediaCodec,
        val width: Int,
        val height: Int,
        val inputSurface: Surface
    )

    /**
     * Picks an H.264 encoder that can really encode the requested size. Some phones only support
     * up to 1080p or 1440p, while Tesla HW4 clips (and 4K sources) can be larger, so the size is
     * stepped down (keeping the aspect ratio) until the device reports a usable encoder.
     */
    private fun createEncoder(
        width: Int,
        height: Int,
        frameRate: Int
    ): EncoderChoice {
        val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        var candidateWidth = width
        var candidateHeight = height
        var lastError: Exception? = null
        var attempt = 0
        while (attempt < 6 && candidateWidth >= 320 && candidateHeight >= 240) {
            val format = MediaFormat.createVideoFormat(MIME_VIDEO_AVC, candidateWidth, candidateHeight).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, estimateBitRate(candidateWidth, candidateHeight, frameRate))
                setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }
            val codecName = try {
                codecList.findEncoderForFormat(format)
            } catch (error: Exception) {
                lastError = error
                null
            }
            if (codecName != null) {
                var codec: MediaCodec? = null
                try {
                    val created = MediaCodec.createByCodecName(codecName)
                    codec = created
                    created.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    val surface = created.createInputSurface()
                    created.start()
                    return EncoderChoice(created, candidateWidth, candidateHeight, surface)
                } catch (error: Exception) {
                    lastError = error
                    runCatching { codec?.release() }
                }
            }
            val nextWidth = align16(candidateWidth * 3 / 4)
            val nextHeight = align16(candidateHeight * 3 / 4)
            if (nextWidth == candidateWidth && nextHeight == candidateHeight) break
            candidateWidth = nextWidth
            candidateHeight = nextHeight
            attempt++
        }
        throw TranscodeException("当前设备无法编码该分辨率（源 " + width + "x" + height + "）", lastError)
    }

    private fun align16(value: Int): Int = (value / 16 * 16).coerceAtLeast(16)

    /** Quick sanity check so an unsupported source size fails fast with a readable message. */
    private fun decoderSupports(mime: String, width: Int, height: Int): Boolean {
        return try {
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            val format = MediaFormat.createVideoFormat(mime, width, height)
            val name = list.findDecoderForFormat(format) ?: return false
            val info = list.codecInfos.firstOrNull { it.name == name } ?: return true
            val video = info.getCapabilitiesForType(mime).videoCapabilities ?: return true
            video.isSizeSupported(width, height)
        } catch (error: Exception) {
            true
        }
    }

    private fun estimateBitRate(width: Int, height: Int, frameRate: Int): Int {
        val bitsPerSecond = width.toLong() * height.toLong() * frameRate * 9L / 100L
        return bitsPerSecond.coerceIn(3_000_000L, 24_000_000L).toInt()
    }
}

/** Drains the encoder into the muxer and interleaves the copied audio samples. */
private class EncoderSink(
    private val encoder: MediaCodec,
    private val muxer: MediaMuxer,
    private val audio: AudioSampleCopier?
) {
    private val info = MediaCodec.BufferInfo()
    private var videoTrackIndex = -1
    private var lastVideoPtsUs = 0L

    var muxerStarted = false
        private set

    fun drain(endOfStream: Boolean) {
        audio?.pumpUpTo(lastVideoPtsUs + 500_000L)
        var idle = 0
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, if (endOfStream) DEQUEUE_TIMEOUT_US else 0L)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) return
                    idle++
                    if (idle > 5000) throw TranscodeException("编码器输出超时")
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    videoTrackIndex = muxer.addTrack(encoder.outputFormat)
                    audio?.attachToMuxer(muxer)
                    muxer.start()
                    muxerStarted = true
                }
                index < 0 -> {
                    if (!endOfStream) return
                }
                else -> {
                    val buffer = encoder.getOutputBuffer(index)
                    if (buffer != null && info.size > 0) {
                        if (!muxerStarted) throw TranscodeException("编码器输出格式尚未就绪")
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSampleData(videoTrackIndex, buffer, info)
                        if (info.presentationTimeUs > lastVideoPtsUs) {
                            lastVideoPtsUs = info.presentationTimeUs
                        }
                    }
                    encoder.releaseOutputBuffer(index, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return
                }
            }
            audio?.pumpUpTo(lastVideoPtsUs + 500_000L)
        }
    }

    fun finishAudio() {
        audio?.flushAll()
    }
}
