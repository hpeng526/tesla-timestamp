package com.teslacam.timestamp.data

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.time.ZoneId

data class ScanResult(
    val groups: List<ClipGroup>,
    val fileCount: Int,
    val sourceLabel: String,
    val warnings: List<String>
)

private data class ScanEntry(
    val relativePath: String,
    val fileName: String,
    val source: MediaSource,
    val sizeBytes: Long,
    val lastModified: Long,
    val identity: ClipIdentity?,
    val eventInfo: TeslaEventInfo?
)

/**
 * Walks a TeslaCam folder tree - either a SAF tree (USB OTG drive, SD card, cloud provider) or a
 * plain file path - and groups the MP4 files into clips the UI can present and process.
 */
class TeslaCamScanner(private val context: Context) {

    private companion object {
        const val MAX_DEPTH = 6
        const val PROGRESS_EVERY = 25
    }

    fun scanTree(
        treeUri: Uri,
        zone: ZoneId = ZoneId.systemDefault(),
        onProgress: ((String) -> Unit)? = null
    ): ScanResult {
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: throw IllegalStateException("无法打开所选目录")
        val entries = mutableListOf<ScanEntry>()
        val warnings = mutableListOf<String>()
        val eventCache = HashMap<String, TeslaEventInfo?>()
        walkDirectory(root, "", 0, entries, warnings, eventCache, zone, onProgress)
        if (entries.isEmpty() && warnings.isEmpty()) {
            warnings += "所选目录中没有找到 TeslaCam 视频（需要 .mp4 文件）"
        }
        return finish(entries, zone, describe(root.name, treeUri))
    }

    fun scanDirectory(
        root: File,
        zone: ZoneId = ZoneId.systemDefault(),
        onProgress: ((String) -> Unit)? = null
    ): ScanResult {
        if (!root.exists()) throw IllegalStateException("路径不存在: " + root.absolutePath)
        if (!root.isDirectory) throw IllegalStateException("不是目录: " + root.absolutePath)
        val entries = mutableListOf<ScanEntry>()
        val warnings = mutableListOf<String>()
        walkFileDirectory(root, root, 0, entries, warnings, zone, onProgress)
        if (entries.isEmpty() && warnings.isEmpty()) {
            warnings += "目录中没有找到 TeslaCam 视频（需要 .mp4 文件）"
        }
        return finish(entries, zone, root.absolutePath)
    }

    fun scanDocument(uri: Uri, zone: ZoneId = ZoneId.systemDefault()): ScanResult {
        return scanDocuments(listOf(uri), sourceLabel = null, zone = zone)
    }

    fun scanDocuments(
        uris: List<Uri>,
        sourceLabel: String? = null,
        zone: ZoneId = ZoneId.systemDefault()
    ): ScanResult {
        val entries = uris.mapIndexed { index, uri ->
            val displayName = documentDisplayName(uri) ?: "video_${index + 1}.mp4"
            val source = MediaSource.Document(uri, displayName)
            val size = source.sizeBytes(context)
            val lastModified = source.lastModified(context)
            val identity = ClipPathParser.parse(displayName, zone)
            ScanEntry(
                relativePath = displayName,
                fileName = displayName,
                source = source,
                sizeBytes = size,
                lastModified = lastModified,
                identity = identity,
                eventInfo = null
            )
        }
        val label = sourceLabel ?: if (entries.size == 1) {
            entries.first().fileName
        } else {
            "相册 · " + entries.size + " 个视频"
        }
        return finish(entries, zone, label)
    }

    fun documentDisplayName(uri: Uri): String? {
        return try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && !cursor.isNull(index)) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (error: Exception) {
            null
        }
    }

    private fun finish(entries: List<ScanEntry>, zone: ZoneId, sourceLabel: String): ScanResult {
        val groups = buildGroups(entries, zone)
        val warnings = mutableListOf<String>()
        val withoutTimestamp = entries.count { it.identity == null }
        if (withoutTimestamp > 0) {
            warnings += withoutTimestamp.toString() + " 个视频文件名中没有 Tesla 时间戳，已按修改时间归组"
        }
        return ScanResult(
            groups = groups,
            fileCount = entries.size,
            sourceLabel = sourceLabel,
            warnings = warnings
        )
    }

    private fun buildGroups(entries: List<ScanEntry>, zone: ZoneId): List<ClipGroup> {
        val grouped = LinkedHashMap<String, MutableList<ScanEntry>>()
        val identities = HashMap<String, ClipIdentity>()
        for (entry in entries) {
            val identity = entry.identity ?: ClipIdentity(
                category = ClipCategory.UNKNOWN,
                clipStartMillis = normalizeFallbackTime(entry.lastModified),
                camera = TeslaNaming.cameraOf(entry.fileName),
                timestampFromName = false
            )
            val groupId = identity.groupId
            identities[groupId] = identity
            grouped.getOrPut(groupId) { mutableListOf() }.add(entry)
        }
        val result = mutableListOf<ClipGroup>()
        for ((groupId, groupEntries) in grouped) {
            val identity = identities.getValue(groupId)
            val files = groupEntries
                .sortedWith(compareBy({ cameraRank(it.fileName) }, { it.fileName }))
                .mapIndexed { index, entry ->
                    ClipFile(
                        id = groupId + "#" + index + "#" + entry.source.key,
                        camera = TeslaNaming.cameraOf(entry.fileName) ?: identity.camera,
                        source = entry.source,
                        sizeBytes = entry.sizeBytes
                    )
                }
            val eventInfo = groupEntries.firstNotNullOfOrNull { it.eventInfo }
            result += ClipGroup(
                id = groupId,
                category = identity.category,
                startEpochMillis = identity.clipStartMillis,
                eventInfo = eventInfo,
                files = files
            )
        }
        return result.sortedWith(
            compareByDescending<ClipGroup> { it.startEpochMillis }.thenBy { it.id }
        )
    }

    private fun normalizeFallbackTime(lastModified: Long): Long {
        val now = System.currentTimeMillis()
        val value = if (lastModified > 0L) lastModified else now
        return value / 1000L * 1000L
    }

    private fun cameraRank(fileName: String): Int = when (TeslaNaming.cameraOf(fileName)) {
        "front" -> 0
        "back" -> 1
        "left_repeater" -> 2
        "right_repeater" -> 3
        "left_pillar" -> 4
        "right_pillar" -> 5
        else -> 9
    }

    private fun walkDirectory(
        directory: DocumentFile,
        relativeDir: String,
        depth: Int,
        entries: MutableList<ScanEntry>,
        warnings: MutableList<String>,
        eventCache: HashMap<String, TeslaEventInfo?>,
        zone: ZoneId,
        onProgress: ((String) -> Unit)?
    ) {
        if (depth > MAX_DEPTH) return
        val children = try {
            directory.listFiles()
        } catch (error: Exception) {
            warnings += "无法读取目录: " + (if (relativeDir.isEmpty()) "/" else relativeDir)
            return
        }
        val directoryEvent = eventInfoFor(directory, eventCache)
        for (child in children) {
            val name = child.name ?: continue
            if (name.startsWith(".")) continue
            val childRelative = if (relativeDir.isEmpty()) name else relativeDir + "/" + name
            if (child.isDirectory) {
                walkDirectory(child, childRelative, depth + 1, entries, warnings, eventCache, zone, onProgress)
                continue
            }
            if (!TeslaNaming.isMp4(name)) continue
            entries += ScanEntry(
                relativePath = childRelative,
                fileName = name,
                source = MediaSource.Document(child.uri, name),
                sizeBytes = child.length(),
                lastModified = child.lastModified(),
                identity = ClipPathParser.parse(childRelative, zone),
                eventInfo = directoryEvent
            )
            if (entries.size % PROGRESS_EVERY == 0) {
                onProgress?.invoke("已找到 " + entries.size + " 个视频 ...")
            }
        }
    }

    private fun walkFileDirectory(
        root: File,
        directory: File,
        depth: Int,
        entries: MutableList<ScanEntry>,
        warnings: MutableList<String>,
        zone: ZoneId,
        onProgress: ((String) -> Unit)?
    ) {
        if (depth > MAX_DEPTH) return
        val children = directory.listFiles() ?: return
        val directoryEvent = readEventJson(File(directory, "event.json"))
        for (child in children) {
            val name = child.name
            if (name.startsWith(".")) continue
            if (child.isDirectory) {
                walkFileDirectory(root, child, depth + 1, entries, warnings, zone, onProgress)
                continue
            }
            if (!TeslaNaming.isMp4(name)) continue
            val relativePath = child.absolutePath.removePrefix(root.absolutePath).trimStart(File.separatorChar)
            val size = try {
                child.length()
            } catch (error: Exception) {
                0L
            }
            entries += ScanEntry(
                relativePath = relativePath,
                fileName = name,
                source = MediaSource.LocalFile(child),
                sizeBytes = size,
                lastModified = child.lastModified(),
                identity = ClipPathParser.parse(relativePath, zone),
                eventInfo = directoryEvent
            )
            if (entries.size % PROGRESS_EVERY == 0) {
                onProgress?.invoke("已找到 " + entries.size + " 个视频 ...")
            }
        }
    }

    private fun eventInfoFor(directory: DocumentFile, cache: HashMap<String, TeslaEventInfo?>): TeslaEventInfo? {
        val key = directory.uri.toString()
        if (cache.containsKey(key)) return cache[key]
        val info = try {
            val json = directory.findFile("event.json")
            if (json != null && json.isFile) {
                context.contentResolver.openInputStream(json.uri)?.use { stream ->
                    val text = stream.readBytes().toString(Charsets.UTF_8)
                    TeslaEventInfo.parse(text)
                }
            } else {
                null
            }
        } catch (error: Exception) {
            null
        }
        cache[key] = info
        return info
    }

    private fun readEventJson(file: File): TeslaEventInfo? {
        return try {
            if (!file.isFile) {
                null
            } else {
                TeslaEventInfo.parse(file.readText(Charsets.UTF_8))
            }
        } catch (error: Exception) {
            null
        }
    }

    private fun describe(name: String?, uri: Uri): String {
        return if (name.isNullOrBlank()) uri.toString() else name
    }
}
