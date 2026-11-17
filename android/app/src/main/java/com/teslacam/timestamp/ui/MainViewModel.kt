package com.teslacam.timestamp.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.teslacam.timestamp.data.ClipFile
import com.teslacam.timestamp.data.ClipGroup
import com.teslacam.timestamp.data.MediaSource
import com.teslacam.timestamp.data.ScanResult
import com.teslacam.timestamp.data.TeslaCamScanner
import com.teslacam.timestamp.data.TeslaNaming
import com.teslacam.timestamp.data.TimeFormats
import com.teslacam.timestamp.export.MediaStoreExporter
import com.teslacam.timestamp.media.OverlayPosition
import com.teslacam.timestamp.media.OverlayStyle
import com.teslacam.timestamp.media.OverlayText
import com.teslacam.timestamp.media.PreviewComposer
import com.teslacam.timestamp.media.TranscodeCancelledException
import com.teslacam.timestamp.media.TranscodeRequest
import com.teslacam.timestamp.media.TimestampVideoProcessor
import java.io.File

data class ExportResult(
    val uri: Uri,
    val displayName: String,
    val durationMs: Long,
    val sizeBytes: Long,
    val startEpochMillis: Long = 0L,
    val cameraLabel: String = ""
) {
    val title: String
        get() = if (startEpochMillis > 0L) {
            TimeFormats.dateTime(startEpochMillis) + " · " + cameraLabel
        } else {
            displayName
        }
}

data class PreviewState(
    val bitmap: android.graphics.Bitmap,
    val caption: String
)

data class UiState(
    val scanning: Boolean = false,
    val scanMessage: String = "",
    val sourceLabel: String = "尚未选择数据来源",
    val groups: List<ClipGroup> = emptyList(),
    val selected: Set<String> = emptySet(),
    val warnings: List<String> = emptyList(),
    val running: Boolean = false,
    val progress: Float = 0f,
    val status: String = "请选择视频",
    val results: List<ExportResult> = emptyList(),
    val error: String? = null,
    val message: String? = null,
    val positionIndex: Int = 0,
    val sizeIndex: Int = 1,
    val showDate: Boolean = true,
    val showDetails: Boolean = false,
    val preview: PreviewState? = null,
    val previewLoading: Boolean = false,
    val failures: List<String> = emptyList()
) {
    val selectedCount: Int get() = selected.size

    fun isGroupFullySelected(group: ClipGroup): Boolean =
        group.files.isNotEmpty() && group.files.all { selected.contains(it.id) }

    fun isGroupPartlySelected(group: ClipGroup): Boolean {
        val anySelected = group.files.any { selected.contains(it.id) }
        return anySelected && !isGroupFullySelected(group)
    }

    fun selectedFiles(): List<Pair<ClipGroup, ClipFile>> =
        groups.flatMap { group -> group.files.filter { selected.contains(it.id) }.map { group to it } }

    val selectedSizeBytes: Long
        get() = groups.sumOf { group ->
            group.files.filter { selected.contains(it.id) }.sumOf { it.sizeBytes }
        }
}

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val scanner = TeslaCamScanner(application)
    private val processor = TimestampVideoProcessor(application)

    private val _state = MutableLiveData(UiState())
    val state: LiveData<UiState> = _state

    private var scanJob: kotlinx.coroutines.Job? = null
    private var workJob: kotlinx.coroutines.Job? = null
    private var lastTreeUri: Uri? = null
    private var lastPath: String? = null
    private var lastDocumentUri: Uri? = null
    private var lastProgressStep = -1

    // ---------------------------------------------------------------- scanning

    fun scanTree(uri: Uri) {
        runCatching {
            getApplication<Application>().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        lastTreeUri = uri
        lastPath = null
        lastDocumentUri = null
        runScan { progress -> scanner.scanTree(uri, onProgress = progress) }
    }

    fun scanPath(rawPath: String) {
        val file = normalizePath(rawPath)
        lastTreeUri = null
        lastPath = file.absolutePath
        lastDocumentUri = null
        runScan { progress -> scanner.scanDirectory(file, onProgress = progress) }
    }

    fun scanDocument(uri: Uri) {
        lastTreeUri = null
        lastPath = null
        lastDocumentUri = uri
        runScan { scanner.scanDocument(uri) }
    }

    fun rescan() {
        val tree = lastTreeUri
        val path = lastPath
        val document = lastDocumentUri
        when {
            tree != null -> scanTree(tree)
            path != null -> scanPath(path)
            document != null -> scanDocument(document)
            else -> post(Message("请先选择 U 盘目录或视频文件"))
        }
    }

    private fun runScan(block: ((String) -> Unit) -> ScanResult) {
        if (_state.value?.running == true) {
            post(Message("正在合成视频，请稍候再扫描"))
            return
        }
        scanJob?.cancel()
        update { it.copy(scanning = true, scanMessage = "正在扫描 ...", error = null, warnings = emptyList()) }
        scanJob = launchIo {
            try {
                val result = block { message -> update { it.copy(scanMessage = message) } }
                applyScan(result)
            } catch (cancel: kotlinx.coroutines.CancellationException) {
                update { it.copy(scanning = false) }
            } catch (error: Exception) {
                update {
                    it.copy(
                        scanning = false,
                        scanMessage = "",
                        error = "扫描失败: " + (error.message ?: "未知错误")
                    )
                }
            }
        }
    }

    private fun applyScan(result: ScanResult) {
        val preselected = result.groups.firstOrNull()?.let { group -> group.files.map { it.id }.toSet() }
            ?: emptySet()
        update {
            it.copy(
                scanning = false,
                groups = result.groups,
                selected = preselected,
                sourceLabel = result.sourceLabel,
                warnings = result.warnings,
                scanMessage = "",
                results = emptyList(),
                progress = 0f,
                status = if (result.fileCount == 0) {
                    "没有找到视频"
                } else {
                    "找到 " + result.groups.size + " 个片段 / " + result.fileCount + " 个视频"
                },
                error = null
            )
        }
    }

    // --------------------------------------------------------------- selection

    fun toggleFile(fileId: String) {
        update { state ->
            val selected = state.selected.toMutableSet()
            if (!selected.add(fileId)) selected.remove(fileId)
            state.copy(selected = selected)
        }
    }

    fun setFileSelected(fileId: String, selected: Boolean) {
        update { state ->
            val next = state.selected.toMutableSet()
            if (selected) next.add(fileId) else next.remove(fileId)
            state.copy(selected = next)
        }
    }

    fun setStyle(positionIndex: Int, sizeIndex: Int, showDate: Boolean, showDetails: Boolean) {
        update {
            it.copy(
                positionIndex = positionIndex.coerceIn(0, OverlayPosition.entries.size - 1),
                sizeIndex = sizeIndex.coerceIn(0, OverlayStyle.SIZE_PRESETS.size - 1),
                showDate = showDate,
                showDetails = showDetails
            )
        }
    }

    /** Selects the given file (if needed) and renders a preview for it. */
    fun requestPreviewFor(fileId: String) {
        update { state -> state.copy(selected = state.selected + fileId) }
        requestPreview()
    }

    fun setGroupSelected(groupId: String, selected: Boolean) {
        update { state ->
            val group = state.groups.firstOrNull { it.id == groupId } ?: return@update state
            val next = state.selected.toMutableSet()
            group.files.forEach { file ->
                if (selected) next.add(file.id) else next.remove(file.id)
            }
            state.copy(selected = next)
        }
    }

    fun selectAll(select: Boolean) {
        update { state ->
            val next = if (select) {
                state.groups.flatMap { group -> group.files.map { it.id } }.toSet()
            } else {
                emptySet()
            }
            state.copy(selected = next)
        }
    }

    // ----------------------------------------------------------------- options

    fun setPositionIndex(index: Int) = update {
        it.copy(positionIndex = index.coerceIn(0, OverlayPosition.entries.size - 1))
    }

    fun setSizeIndex(index: Int) = update {
        it.copy(sizeIndex = index.coerceIn(0, OverlayStyle.SIZE_PRESETS.size - 1))
    }

    fun setShowDate(value: Boolean) = update { it.copy(showDate = value) }

    fun setShowDetails(value: Boolean) = update { it.copy(showDetails = value) }

    // ----------------------------------------------------------------- preview

    /**
     * Renders a still preview of the first selected clip with the current overlay style, so the user
     * can see exactly where and how big the burned in timestamp will be before starting the encode.
     */
    fun requestPreview() {
        val state = currentState
        val pair = state.selectedFiles().firstOrNull()
            ?: state.groups.firstOrNull()?.let { group ->
                group.files.firstOrNull()?.let { file -> group to file }
            }
        if (pair == null) {
            post(Message("请先选择视频"))
            return
        }
        if (state.previewLoading) return
        val style = currentStyle(state)
        val group = pair.first
        val file = pair.second
        update { it.copy(previewLoading = true) }
        launchIo {
            val detail = if (style.showDetails) {
                OverlayText.detailLine(TeslaNaming.cameraLabel(file.camera), group.eventInfo)
            } else {
                null
            }
            val bitmap = try {
                PreviewComposer.compose(
                    getApplication(),
                    file.source,
                    group.startEpochMillis,
                    style,
                    detail
                )
            } catch (error: Exception) {
                null
            }
            if (bitmap == null) {
                update { it.copy(previewLoading = false, error = "无法生成预览") }
            } else {
                val caption = "画面时间 " + OverlayText.firstLine(
                    group.startEpochMillis + 1000L,
                    style
                ) + " · " + TeslaNaming.cameraLabel(file.camera)
                update { it.copy(previewLoading = false, preview = PreviewState(bitmap, caption)) }
            }
        }
    }

    fun dismissPreview() = update { it.copy(preview = null) }

    private fun currentStyle(state: UiState) = OverlayStyle(
        position = OverlayPosition.entries[state.positionIndex],
        textScale = OverlayStyle.SIZE_PRESETS[state.sizeIndex],
        showDate = state.showDate,
        showDetails = state.showDetails
    )

    // ---------------------------------------------------------------- generate

    fun generate() {
        val current = currentState
        if (current.running) return
        val items = current.selectedFiles()
        if (items.isEmpty()) {
            post(Message("请先勾选要处理的视频"))
            return
        }
        val style = currentStyle(current)
        val application = getApplication<Application>()
        lastProgressStep = -1
        update {
            it.copy(
                running = true,
                progress = 0f,
                status = "准备合成 ...",
                error = null,
                results = emptyList()
            )
        }
        workJob = launchDefault {
            val results = mutableListOf<ExportResult>()
            val failures = mutableListOf<String>()
            try {
                items.forEachIndexed { index, pair ->
                    val group = pair.first
                    val file = pair.second
                    val cameraLabel = TeslaNaming.cameraLabel(file.camera)
                    val label = cameraLabel + " · " + TimeFormats.dateTime(group.startEpochMillis)
                    update {
                        it.copy(
                            status = "正在合成 " + (index + 1) + "/" + items.size + "：" + label
                        )
                    }
                    val temp = File(
                        application.cacheDir,
                        "timestamp_" + System.currentTimeMillis() + "_" + index + ".mp4"
                    )
                    val base = index.toFloat() / items.size
                    val step = 1f / items.size
                    try {
                        val detail = if (style.showDetails) {
                            OverlayText.detailLine(cameraLabel, group.eventInfo)
                        } else {
                            null
                        }
                        val request = TranscodeRequest(
                            source = file.source,
                            outputFile = temp,
                            startEpochMillis = group.startEpochMillis,
                            style = style,
                            detailText = detail
                        )
                        val result = processor.process(request) { fraction ->
                            val overall = base + fraction * step
                            val bucket = (overall * 100).toInt()
                            if (bucket != lastProgressStep) {
                                lastProgressStep = bucket
                                update { it.copy(progress = overall) }
                            }
                        }
                        val displayName = outputName(group, file)
                        val uri = MediaStoreExporter.export(application, temp, displayName)
                        results += ExportResult(
                            uri = uri,
                            displayName = displayName,
                            durationMs = result.durationMs,
                            sizeBytes = temp.length(),
                            startEpochMillis = group.startEpochMillis,
                            cameraLabel = cameraLabel
                        )
                        update { it.copy(results = results.toList()) }
                    } catch (cancel: TranscodeCancelledException) {
                        throw cancel
                    } catch (error: Exception) {
                        failures += label + "：" + (error.message ?: "处理失败")
                    } finally {
                        if (temp.exists()) temp.delete()
                    }
                }
                if (results.isEmpty()) {
                    update {
                        it.copy(
                            running = false,
                            progress = 0f,
                            status = "合成失败",
                            failures = failures.toList(),
                            error = failures.firstOrNull() ?: "没有生成视频"
                        )
                    }
                } else {
                    update {
                        it.copy(
                            running = false,
                            progress = 1f,
                            status = if (failures.isEmpty()) {
                                "完成：" + results.size + " 个视频已导出到相册 Movies/TeslaTimestamp"
                            } else {
                                "完成 " + results.size + " 个，失败 " + failures.size + " 个"
                            },
                            results = results.toList(),
                            failures = failures.toList(),
                            error = null
                        )
                    }
                }
            } catch (cancel: TranscodeCancelledException) {
                update { it.copy(running = false, progress = 0f, status = "已取消") }
            } catch (cancel: kotlinx.coroutines.CancellationException) {
                update { it.copy(running = false, progress = 0f, status = "已取消") }
            } catch (error: Exception) {
                update {
                    it.copy(
                        running = false,
                        progress = 0f,
                        status = "合成失败",
                        error = error.message ?: "合成失败"
                    )
                }
            }
        }
    }

    fun cancelWork() {
        processor.cancel()
        workJob?.cancel()
        update { it.copy(status = "正在取消 ...") }
    }

    fun dismissError() = update { it.copy(error = null) }

    fun dismissMessage() = update { it.copy(message = null) }

    // ------------------------------------------------------------------ helper

    private fun outputName(group: ClipGroup, file: ClipFile): String {
        val stamp = TimeFormats.dateTime(group.startEpochMillis).replace(":", "-").replace(" ", "_")
        val camera = file.camera ?: "video"
        return stamp + "_" + camera + "_timestamped.mp4"
    }

    private fun normalizePath(raw: String): File {
        var path = raw.trim()
        if (path.isEmpty()) throw IllegalArgumentException("路径为空")
        if (path.startsWith("~/")) {
            path = path.substring(2)
        }
        if (!path.startsWith("/")) {
            path = "/storage/emulated/0/" + path
        }
        return File(path)
    }

    @Volatile
    private var currentState = UiState()

    private fun update(block: (UiState) -> UiState) {
        synchronized(this) {
            currentState = block(currentState)
            _state.postValue(currentState)
        }
    }

    private fun post(message: Message) {
        update { it.copy(message = message.text) }
    }

    private data class Message(val text: String)
}
