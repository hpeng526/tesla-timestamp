package com.teslacam.timestamp.media

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.TimeUnit
import kotlin.math.max

/**
 * Owns the EGL context, the SurfaceTexture the decoder renders into, and the GL program that blits
 * that texture into the encoder Surface while burning in the timestamp overlay.
 *
 * Pipeline: MediaCodec decoder -> SurfaceTexture (external OES texture) -> GL draw with overlay ->
 * MediaCodec encoder input Surface.
 */
internal class GlTimestampRenderer(
    private val outputWidth: Int,
    private val outputHeight: Int,
    private val rotationDegrees: Int
) {

    private companion object {
        const val EGL_RECORDABLE_ANDROID = 0x3142
        const val FRAME_TIMEOUT_MS = 5000L

        val FULL_SCREEN_VERTICES = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
        val FULL_SCREEN_TEX_COORDS = floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f)

        val VIDEO_VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            uniform mat4 uTexMatrix;
            uniform float uRotation;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vec2 tex = (uTexMatrix * vec4(aTexCoord, 0.0, 1.0)).xy;
                vec2 center = vec2(0.5, 0.5);
                float s = sin(uRotation);
                float c = cos(uRotation);
                mat2 rot = mat2(c, -s, s, c);
                vTexCoord = rot * (tex - center) + center;
            }
        """.trimIndent()

        val VIDEO_FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES sTexture;
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = texture2D(sTexture, vTexCoord);
            }
        """.trimIndent()

        val OVERLAY_VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord;
            }
        """.trimIndent()

        val OVERLAY_FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D sTexture;
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = texture2D(sTexture, vTexCoord);
            }
        """.trimIndent()
    }

    private val eglDisplay: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private val eglConfig: EGLConfig
    private val eglContext: EGLContext
    private var eglEncoderSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var eglPbufferSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private val supportsPresentationTime: Boolean

    private val externalTextureId: Int
    val surfaceTexture: SurfaceTexture
    val videoSurface: Surface

    private var videoProgram = 0
    private var videoPositionHandle = 0
    private var videoTexCoordHandle = 0
    private var videoTexMatrixHandle = 0
    private var videoRotationHandle = 0
    private var videoSamplerHandle = 0
    private val vertexBuffer: FloatBuffer
    private val texCoordBuffer: FloatBuffer

    private var overlayProgram = 0
    private var overlayPositionHandle = 0
    private var overlayTexCoordHandle = 0
    private var overlaySamplerHandle = 0
    private var overlayTextureId = 0
    private val overlayVertexBuffer: FloatBuffer
    private val overlayTexCoordBuffer: FloatBuffer

    private var overlayWidth = 0
    private var overlayHeight = 0
    private var overlayX = 0
    private var overlayY = 0
    private var overlayKey: String? = null
    private var programsReady = false

    private val texMatrix = FloatArray(16)
    private val frameLock = java.util.concurrent.locks.ReentrantLock()
    private val frameSignal = frameLock.newCondition()
    private var frameAvailable = false
    private var released = false

    init {
        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            throw IllegalStateException("无法初始化 EGL")
        }
        val configAttribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        val chosen = EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0)
        if (!chosen || numConfigs[0] == 0 || configs[0] == null) {
            throw IllegalStateException("没有可用的 EGL 配置")
        }
        eglConfig = configs[0]!!
        val contextAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        val context = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
        if (context == null || context == EGL14.EGL_NO_CONTEXT) {
            throw IllegalStateException("无法创建 EGL 上下文")
        }
        eglContext = context
        val extensions = EGL14.eglQueryString(eglDisplay, EGL14.EGL_EXTENSIONS)
        supportsPresentationTime = extensions != null && extensions.contains("EGL_ANDROID_presentation_time")

        eglPbufferSurface = createPbufferSurface()
        makeCurrent(eglPbufferSurface)

        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        externalTextureId = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, externalTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)

        surfaceTexture = SurfaceTexture(externalTextureId)
        videoSurface = Surface(surfaceTexture)
        surfaceTexture.setOnFrameAvailableListener {
            frameLock.lock()
            try {
                frameAvailable = true
                frameSignal.signalAll()
            } finally {
                frameLock.unlock()
            }
        }

        vertexBuffer = toFloatBuffer(FULL_SCREEN_VERTICES)
        texCoordBuffer = toFloatBuffer(FULL_SCREEN_TEX_COORDS)
        overlayVertexBuffer = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        overlayTexCoordBuffer = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        createOverlayTexture()
    }

    /** Attaches the renderer to the encoder input Surface and compiles the GL programs. */
    fun createEncoderSurface(inputSurface: Surface) {
        val attribs = intArrayOf(EGL14.EGL_NONE)
        val surface = EGL14.eglCreateWindowSurface(eglDisplay, eglConfig, inputSurface, attribs, 0)
        if (surface == null || surface == EGL14.EGL_NO_SURFACE) {
            throw IllegalStateException("无法为编码器创建 EGL 表面")
        }
        eglEncoderSurface = surface
        makeCurrent(surface)

        videoProgram = buildProgram(VIDEO_VERTEX_SHADER, VIDEO_FRAGMENT_SHADER)
        videoPositionHandle = GLES20.glGetAttribLocation(videoProgram, "aPosition")
        videoTexCoordHandle = GLES20.glGetAttribLocation(videoProgram, "aTexCoord")
        videoTexMatrixHandle = GLES20.glGetUniformLocation(videoProgram, "uTexMatrix")
        videoRotationHandle = GLES20.glGetUniformLocation(videoProgram, "uRotation")
        videoSamplerHandle = GLES20.glGetUniformLocation(videoProgram, "sTexture")

        overlayProgram = buildProgram(OVERLAY_VERTEX_SHADER, OVERLAY_FRAGMENT_SHADER)
        overlayPositionHandle = GLES20.glGetAttribLocation(overlayProgram, "aPosition")
        overlayTexCoordHandle = GLES20.glGetAttribLocation(overlayProgram, "aTexCoord")
        overlaySamplerHandle = GLES20.glGetUniformLocation(overlayProgram, "sTexture")

        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        programsReady = true
    }

    /**
     * Blocks until the decoder produced a new frame, uploads it into the external texture and
     * returns its presentation timestamp in nanoseconds.
     */
    fun awaitNewFrame(): Long {
        frameLock.lock()
        try {
            val deadline = System.currentTimeMillis() + FRAME_TIMEOUT_MS
            while (!frameAvailable) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0L) {
                    throw IllegalStateException("等待解码帧超时")
                }
                try {
                    frameSignal.await(remaining, TimeUnit.MILLISECONDS)
                } catch (interrupted: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw IllegalStateException("等待解码帧被中断", interrupted)
                }
            }
            frameAvailable = false
        } finally {
            frameLock.unlock()
        }
        surfaceTexture.updateTexImage()
        return surfaceTexture.timestamp
    }

    /** Draws one frame (video + overlay) into the encoder surface. */
    fun drawFrame(lines: List<String>, style: OverlayStyle) {
        check(programsReady) { "渲染器尚未就绪" }
        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        GLES20.glUseProgram(videoProgram)
        surfaceTexture.getTransformMatrix(texMatrix)
        GLES20.glUniformMatrix4fv(videoTexMatrixHandle, 1, false, texMatrix, 0)
        GLES20.glUniform1f(videoRotationHandle, Math.toRadians(rotationDegrees.toDouble()).toFloat())
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, externalTextureId)
        GLES20.glUniform1i(videoSamplerHandle, 0)

        vertexBuffer.position(0)
        GLES20.glVertexAttribPointer(videoPositionHandle, 2, GLES20.GL_FLOAT, false, 0, vertexBuffer)
        GLES20.glEnableVertexAttribArray(videoPositionHandle)
        texCoordBuffer.position(0)
        GLES20.glVertexAttribPointer(videoTexCoordHandle, 2, GLES20.GL_FLOAT, false, 0, texCoordBuffer)
        GLES20.glEnableVertexAttribArray(videoTexCoordHandle)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(videoPositionHandle)
        GLES20.glDisableVertexAttribArray(videoTexCoordHandle)

        drawOverlay(lines, style)
    }

    /** Hands the frame to the encoder together with its presentation timestamp. */
    fun presentFrame(presentationTimeNs: Long) {
        if (eglEncoderSurface == EGL14.EGL_NO_SURFACE) return
        if (supportsPresentationTime) {
            EGLExt.eglPresentationTimeANDROID(eglDisplay, eglEncoderSurface, presentationTimeNs)
        }
        if (!EGL14.eglSwapBuffers(eglDisplay, eglEncoderSurface)) {
            throw IllegalStateException("eglSwapBuffers 失败: " + EGL14.eglGetError())
        }
    }

    private fun drawOverlay(lines: List<String>, style: OverlayStyle) {
        val textSizePx = max(10f, outputHeight * style.textFraction)
        val key = lines.joinToString("\n") + "|" + style.position.name + "|" +
            style.textScale + "|" + outputWidth + "x" + outputHeight + "|" + (style.boxAlpha * 100).toInt()
        if (key != overlayKey) {
            val bitmap = OverlayBitmapFactory.create(lines, textSizePx, style)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            overlayWidth = bitmap.width
            overlayHeight = bitmap.height
            bitmap.recycle()
            overlayKey = key
            positionOverlay(style)
        }
        if (overlayWidth <= 0 || overlayHeight <= 0) return

        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glUseProgram(overlayProgram)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId)
        GLES20.glUniform1i(overlaySamplerHandle, 0)

        overlayVertexBuffer.position(0)
        GLES20.glVertexAttribPointer(overlayPositionHandle, 2, GLES20.GL_FLOAT, false, 0, overlayVertexBuffer)
        GLES20.glEnableVertexAttribArray(overlayPositionHandle)
        overlayTexCoordBuffer.position(0)
        GLES20.glVertexAttribPointer(overlayTexCoordHandle, 2, GLES20.GL_FLOAT, false, 0, overlayTexCoordBuffer)
        GLES20.glEnableVertexAttribArray(overlayTexCoordHandle)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(overlayPositionHandle)
        GLES20.glDisableVertexAttribArray(overlayTexCoordHandle)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun positionOverlay(style: OverlayStyle) {
        val margin = max(4, (outputHeight * style.marginFraction).toInt())
        overlayX = when (style.position) {
            OverlayPosition.TOP_LEFT, OverlayPosition.BOTTOM_LEFT -> margin
            else -> max(margin, outputWidth - margin - overlayWidth)
        }
        overlayY = when (style.position) {
            OverlayPosition.TOP_LEFT, OverlayPosition.TOP_RIGHT -> margin
            else -> max(margin, outputHeight - margin - overlayHeight)
        }
        val left = overlayX.toFloat() / outputWidth * 2f - 1f
        val right = (overlayX + overlayWidth).toFloat() / outputWidth * 2f - 1f
        val top = 1f - overlayY.toFloat() / outputHeight * 2f
        val bottom = 1f - (overlayY + overlayHeight).toFloat() / outputHeight * 2f
        overlayVertexBuffer.clear()
        overlayVertexBuffer.put(floatArrayOf(left, bottom, right, bottom, left, top, right, top))
        overlayVertexBuffer.position(0)
        overlayTexCoordBuffer.clear()
        overlayTexCoordBuffer.put(floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f))
        overlayTexCoordBuffer.position(0)
    }

    fun release() {
        if (released) return
        released = true
        try {
            surfaceTexture.release()
        } catch (ignored: Exception) {
        }
        try {
            videoSurface.release()
        } catch (ignored: Exception) {
        }
        if (eglEncoderSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(eglDisplay, eglEncoderSurface)
            eglEncoderSurface = EGL14.EGL_NO_SURFACE
        }
        if (eglPbufferSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(eglDisplay, eglPbufferSurface)
            eglPbufferSurface = EGL14.EGL_NO_SURFACE
        }
        if (videoProgram != 0) GLES20.glDeleteProgram(videoProgram)
        if (overlayProgram != 0) GLES20.glDeleteProgram(overlayProgram)
        if (eglContext != EGL14.EGL_NO_CONTEXT) {
            EGL14.eglDestroyContext(eglDisplay, eglContext)
            EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglReleaseThread()
        }
        EGL14.eglTerminate(eglDisplay)
    }

    private fun createOverlayTexture() {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        overlayTextureId = textures[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    }

    private fun createPbufferSurface(): EGLSurface {
        val attribs = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
        val surface = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, attribs, 0)
        if (surface == null || surface == EGL14.EGL_NO_SURFACE) {
            throw IllegalStateException("无法创建 EGL 缓冲表面")
        }
        return surface
    }

    private fun makeCurrent(surface: EGLSurface) {
        if (!EGL14.eglMakeCurrent(eglDisplay, surface, surface, eglContext)) {
            throw IllegalStateException("eglMakeCurrent 失败: " + EGL14.eglGetError())
        }
    }

    private fun buildProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)
        val status = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw IllegalStateException("GL 程序链接失败: " + log)
        }
        GLES20.glDeleteShader(vertexShader)
        GLES20.glDeleteShader(fragmentShader)
        return program
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw IllegalStateException("GL 着色器编译失败: " + log)
        }
        return shader
    }

    private fun toFloatBuffer(values: FloatArray): FloatBuffer {
        val buffer = ByteBuffer.allocateDirect(values.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        buffer.put(values)
        buffer.position(0)
        return buffer
    }
}
