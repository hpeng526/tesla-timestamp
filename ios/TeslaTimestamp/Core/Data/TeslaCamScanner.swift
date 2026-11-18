import Foundation

public struct ScanResult: Sendable, Equatable {
    public let groups: [ClipGroup]
    public let fileCount: Int
    public let sourceLabel: String
    public let warnings: [String]

    public init(
        groups: [ClipGroup],
        fileCount: Int,
        sourceLabel: String,
        warnings: [String]
    ) {
        self.groups = groups
        self.fileCount = fileCount
        self.sourceLabel = sourceLabel
        self.warnings = warnings
    }
}

public enum ScanError: LocalizedError {
    case notFound(String)
    case notDirectory(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "路径不存在: \(path)"
        case .notDirectory(let path):
            return "不是目录: \(path)"
        case .unreadable(let name):
            return "无法打开所选目录: \(name)"
        }
    }
}

private struct ScanEntry {
    let relativePath: String
    let fileName: String
    let source: MediaSource
    let sizeBytes: Int64
    let lastModified: Int64
    let identity: ClipIdentity?
    let eventInfo: TeslaEventInfo?
}

/// Walks a TeslaCam folder tree - either a security-scoped external USB drive / Files folder or a
/// local path - and groups the MP4 files into clips the UI can present and process.
public final class TeslaCamScanner: Sendable {

    private static let maxDepth = 6
    private static let progressEvery = 25

    public init() {}

    public func scanFolder(
        url: URL,
        securityScoped: Bool = true,
        timeZone: TimeZone = .current,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) throws -> ScanResult {
        let started = securityScoped ? url.startAccessingSecurityScopedResource() : false
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }

        let standardizedRoot = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedRoot.path, isDirectory: &isDir) else {
            throw ScanError.notFound(standardizedRoot.path)
        }
        guard isDir.boolValue else {
            throw ScanError.notDirectory(standardizedRoot.path)
        }

        var entries: [ScanEntry] = []
        var warnings: [String] = []
        let scopeRoot: URL? = securityScoped ? url : nil

        walkDirectory(
            root: standardizedRoot,
            directory: standardizedRoot,
            relativeDir: "",
            depth: 0,
            scopeRoot: scopeRoot,
            entries: &entries,
            warnings: &warnings,
            timeZone: timeZone,
            onProgress: onProgress
        )

        if entries.isEmpty && warnings.isEmpty {
            warnings.append("所选目录中没有找到 TeslaCam 视频（需要 .mp4 文件）")
        }

        let label = describeFolder(url: url)
        return finish(entries: entries, extraWarnings: warnings, sourceLabel: label)
    }

    public func scanSingleFile(
        url: URL,
        securityScoped: Bool = true,
        timeZone: TimeZone = .current
    ) throws -> ScanResult {
        let started = securityScoped ? url.startAccessingSecurityScopedResource() : false
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScanError.notFound(url.lastPathComponent)
        }

        let displayName = url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent
        let source = MediaSource(
            url: url,
            displayName: displayName,
            securityScopeRootURL: securityScoped ? url : nil
        )
        let size = source.sizeBytes()
        let lastModified = source.lastModifiedMillis()
        let identity = ClipPathParser.parse(displayName, timeZone: timeZone)

        // Also check sibling event.json if accessible (e.g. when picking from SavedClips folder).
        let parentEvent = readEventJson(at: url.deletingLastPathComponent().appendingPathComponent("event.json"))

        let entry = ScanEntry(
            relativePath: displayName,
            fileName: displayName,
            source: source,
            sizeBytes: size,
            lastModified: lastModified,
            identity: identity,
            eventInfo: parentEvent
        )
        return finish(entries: [entry], extraWarnings: [], sourceLabel: displayName)
    }

    // MARK: - Private

    private func finish(
        entries: [ScanEntry],
        extraWarnings: [String],
        sourceLabel: String
    ) -> ScanResult {
        let groups = buildGroups(entries: entries)
        var warnings = extraWarnings
        let withoutTimestamp = entries.filter { $0.identity == nil }.count
        if withoutTimestamp > 0 {
            warnings.append("\(withoutTimestamp) 个视频文件名中没有 Tesla 时间戳，已按修改时间归组")
        }
        return ScanResult(
            groups: groups,
            fileCount: entries.count,
            sourceLabel: sourceLabel,
            warnings: warnings
        )
    }

    private func buildGroups(entries: [ScanEntry]) -> [ClipGroup] {
        var orderedGroupIds: [String] = []
        var grouped: [String: [ScanEntry]] = [:]
        var identities: [String: ClipIdentity] = [:]

        for entry in entries {
            let identity = entry.identity ?? ClipIdentity(
                category: .unknown,
                clipStartMillis: normalizeFallbackTime(entry.lastModified),
                camera: TeslaNaming.cameraOf(entry.fileName),
                timestampFromName: false
            )
            let groupId = identity.groupId
            if grouped[groupId] == nil {
                orderedGroupIds.append(groupId)
                grouped[groupId] = []
            }
            identities[groupId] = identity
            grouped[groupId]?.append(entry)
        }

        var result: [ClipGroup] = []
        result.reserveCapacity(orderedGroupIds.count)

        for groupId in orderedGroupIds {
            guard let groupEntries = grouped[groupId],
                  let identity = identities[groupId] else { continue }

            let sortedEntries = groupEntries.sorted { lhs, rhs in
                let rankL = cameraRank(lhs.fileName)
                let rankR = cameraRank(rhs.fileName)
                if rankL != rankR { return rankL < rankR }
                return lhs.fileName < rhs.fileName
            }

            let files = sortedEntries.enumerated().map { index, entry in
                ClipFile(
                    id: "\(groupId)#\(index)#\(entry.source.key)",
                    camera: TeslaNaming.cameraOf(entry.fileName) ?? identity.camera,
                    source: entry.source,
                    sizeBytes: entry.sizeBytes
                )
            }

            let eventInfo = groupEntries.compactMap(\.eventInfo).first
            result.append(
                ClipGroup(
                    id: groupId,
                    category: identity.category,
                    startEpochMillis: identity.clipStartMillis,
                    eventInfo: eventInfo,
                    files: files
                )
            )
        }

        return result.sorted { lhs, rhs in
            if lhs.startEpochMillis != rhs.startEpochMillis {
                return lhs.startEpochMillis > rhs.startEpochMillis
            }
            return lhs.id < rhs.id
        }
    }

    private func normalizeFallbackTime(_ lastModified: Int64) -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let value = lastModified > 0 ? lastModified : now
        return (value / 1000) * 1000
    }

    private func cameraRank(_ fileName: String) -> Int {
        switch TeslaNaming.cameraOf(fileName) {
        case "front": return 0
        case "back": return 1
        case "left_repeater": return 2
        case "right_repeater": return 3
        case "left_pillar": return 4
        case "right_pillar": return 5
        default: return 9
        }
    }

    private func walkDirectory(
        root: URL,
        directory: URL,
        relativeDir: String,
        depth: Int,
        scopeRoot: URL?,
        entries: inout [ScanEntry],
        warnings: inout [String],
        timeZone: TimeZone,
        onProgress: (@Sendable (String) -> Void)?
    ) {
        if depth > Self.maxDepth { return }

        let resourceKeys: [URLResourceKey] = [
            .nameKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            let display = relativeDir.isEmpty ? "/" : relativeDir
            warnings.append("无法读取目录: \(display)")
            return
        }

        let directoryEvent = readEventJson(at: directory.appendingPathComponent("event.json"))

        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }

            let values = try? child.resourceValues(forKeys: Set(resourceKeys))
            let isDir = values?.isDirectory ?? false
            let childRelative = relativeDir.isEmpty ? name : "\(relativeDir)/\(name)"

            if isDir {
                walkDirectory(
                    root: root,
                    directory: child,
                    relativeDir: childRelative,
                    depth: depth + 1,
                    scopeRoot: scopeRoot,
                    entries: &entries,
                    warnings: &warnings,
                    timeZone: timeZone,
                    onProgress: onProgress
                )
                continue
            }

            guard TeslaNaming.isMp4(name) else { continue }

            let size = Int64(values?.fileSize ?? 0)
            let modifiedMillis: Int64
            if let modDate = values?.contentModificationDate {
                modifiedMillis = Int64(modDate.timeIntervalSince1970 * 1000.0)
            } else {
                modifiedMillis = 0
            }

            let source = MediaSource(
                url: child,
                displayName: name,
                securityScopeRootURL: scopeRoot
            )

            entries.append(
                ScanEntry(
                    relativePath: childRelative,
                    fileName: name,
                    source: source,
                    sizeBytes: size,
                    lastModified: modifiedMillis,
                    identity: ClipPathParser.parse(childRelative, timeZone: timeZone),
                    eventInfo: directoryEvent
                )
            )

            if entries.count % Self.progressEvery == 0 {
                onProgress?("已找到 \(entries.count) 个视频 ...")
            }
        }
    }

    private func readEventJson(at url: URL) -> TeslaEventInfo? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return TeslaEventInfo.parse(text)
    }

    private func describeFolder(url: URL) -> String {
        let name = url.lastPathComponent
        if let volumeValues = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey]),
           let volumeName = volumeValues.volumeName,
           (volumeValues.volumeIsRemovable == true || volumeValues.volumeIsInternal == false),
           volumeName != name {
            return "\(volumeName) / \(name)"
        }
        return name.isEmpty ? url.path : name
    }
}
