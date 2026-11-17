package com.teslacam.timestamp.media

import android.content.Context

/**
 * Public entry point of the compositing pipeline. One instance handles one clip at a time and can be
 * cancelled from any thread.
 */
class TimestampVideoProcessor(private val context: Context) {

    @Volatile
    private var active: TimestampTranscoder? = null

    fun cancel() {
        active?.cancel()
    }

    private fun describe(error: Throwable): String {
        if (error is android.media.MediaCodec.CodecException) {
            return "设备硬件编解码器处理失败（分辨率过高或资源不足，错误码 " +
                error.errorCode + "）"
        }
        val message = error.message
        return if (message.isNullOrBlank()) "视频处理失败（" + error.javaClass.simpleName + "）" else message
    }

    /**
     * Runs the whole pipeline and writes the timestamped MP4 to [TranscodeRequest.outputFile].
     * Throws [TranscodeCancelledException] when [cancel] was called and [TranscodeException] for any
     * media failure. The partially written file is removed on failure.
     */
    fun process(request: TranscodeRequest, onProgress: (Float) -> Unit = {}): TranscodeResult {
        val output = request.outputFile
        output.parentFile?.mkdirs()
        if (output.exists()) output.delete()
        val transcoder = TimestampTranscoder(context, request)
        active = transcoder
        try {
            return transcoder.transcode(onProgress)
        } catch (cancelled: TranscodeCancelledException) {
            output.delete()
            throw cancelled
        } catch (error: TranscodeException) {
            output.delete()
            throw error
        } catch (error: Exception) {
            output.delete()
            throw TranscodeException(describe(error), error)
        } finally {
            if (active === transcoder) active = null
        }
    }
}
