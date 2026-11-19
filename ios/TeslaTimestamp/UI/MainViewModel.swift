#if canImport(UIKit)
import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct ExportResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let displayName: String
    public let durationMs: Int64
    public let sizeBytes: Int64
    public let startEpochMillis: Int64
    public let cameraLabel: String

    public init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        durationMs: Int64,
        sizeBytes: Int64,
        startEpochMillis: Int64 = 0,
        cameraLabel: String = ""
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
        self.startEpochMillis = startEpochMillis
        self.cameraLabel = cameraLabel
    }

    public var title: String {
        if startEpochMillis > 0 {
            return "\(TimeFormats.dateTime(startEpochMillis)) · \(cameraLabel)"
        }
        return displayName
    }
}

public struct PreviewState: Identifiable {
    public let id = UUID()
    public let image: UIImage
    public let caption: String
}

public struct PlayerSheetItem: Identifiable {
    public let id = UUID()
    public let url: URL
    public let title: String
}

public struct ShareSheetItem: Identifiable {
    public let id = UUID()
    public let url: URL
}

@MainActor
public final class MainViewModel: ObservableObject {

    // MARK: - Published UI State

    @Published public var scanning: Bool = false
    @Published public var scanMessage: String = ""
    @Published public var sourceLabel: String = "尚未选择 TeslaCam 文件夹"
    @Published public var hasChosenSource: Bool = false
    @Published public var groups: [ClipGroup] = []
    @Published public var selected: Set<String> = []
    @Published public var warnings: [String] = []

    @Published public var running: Bool = false
    @Published public var progress: Float = 0
    @Published public var status: String = "请选择视频"
    @Published public var results: [ExportResult] = []
    @Published public var failures: [String] = []
    @Published public var doneVisible: Bool = false

    @Published public var positionIndex: Int = 0
    @Published public var sizeIndex: Int = 1
    @Published public var showDate: Bool = true
    @Published public var showDetails: Bool = false

    @Published public var preview: PreviewState?
    @Published public var previewLoading: Bool = false

    @Published public var showResultsSheet: Bool = false
    @Published public var activePlayerItem: PlayerSheetItem?
    @Published public var activeShareItem: ShareSheetItem?
    @Published public var alertError: String?
    @Published public var toastMessage: String?

    @Published public var usbPillText: String = "U 盘未连接"
    @Published public var usbConnected: Bool = false

    // MARK: - Private Services & Session State

    private let scanner = TeslaCamScanner()
    private let processor = TimestampVideoProcessor()

    private enum LastSource {
        case folder(URL)
        case singleFile(URL)
        case albumFiles([URL], String?)
    }

    private var lastSource: LastSource?
    private var activeSecurityScopedURL: URL?
    private var importedAlbumDirectory: URL?
    private var scanTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    public init() {
        refreshUsbStatus()
    }

    deinit {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        if let dir = importedAlbumDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Computed Helpers

    public var selectedCount: Int {
        selected.count
    }

    public var totalFileCount: Int {
        groups.reduce(0) { $0 + $1.files.count }
    }

    public var selectedSizeBytes: Int64 {
        groups.reduce(0) { acc, group in
            let sum = group.files.filter { selected.contains($0.id) }.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return acc + sum
        }
    }

    public var currentStyle: OverlayStyle {
        let positions = OverlayPosition.allCases
        let safePos = positions[min(max(0, positionIndex), positions.count - 1)]
        let presets = OverlayStyle.sizePresets
        let safeScale = presets[min(max(0, sizeIndex), presets.count - 1)]
        return OverlayStyle(
            position: safePos,
            textScale: safeScale,
            showDate: showDate,
            showDetails: showDetails
        )
    }

    public var styleSummaryText: String {
        let positions = OverlayPosition.allCases
        let posLabel = positions[min(max(0, positionIndex), positions.count - 1)].label
        let sizeLabel = OverlayStyle.sizeLabels[min(max(0, sizeIndex), OverlayStyle.sizeLabels.count - 1)]
        let suffix = showDetails ? " · 含摄像头/地点" : ""
        return "位置 \(posLabel) · 字号 \(sizeLabel)\(suffix)"
    }

    public func isGroupFullySelected(_ group: ClipGroup) -> Bool {
        !group.files.isEmpty && group.files.allSatisfy { selected.contains($0.id) }
    }

    public func isGroupPartlySelected(_ group: ClipGroup) -> Bool {
        let anySelected = group.files.contains { selected.contains($0.id) }
        return anySelected && !isGroupFullySelected(group)
    }

    public func selectedFiles() -> [(group: ClipGroup, file: ClipFile)] {
        groups.flatMap { group in
            group.files.filter { selected.contains($0.id) }.map { (group: group, file: $0) }
        }
    }

    // MARK: - USB Status

    public func refreshUsbStatus() {
        let activeURL: URL?
        switch lastSource {
        case .folder(let url), .singleFile(let url):
            activeURL = url
        case .albumFiles, .none:
            activeURL = nil
        }
        let names = UsbVolumeMonitor.attachedVolumeNames(activeSourceURL: activeURL)
        usbConnected = !names.isEmpty
        if let first = names.first {
            usbPillText = String(first.prefix(14))
        } else {
            usbPillText = "U 盘未连接"
        }
    }

    // MARK: - Scanning

    public func scanFolder(url: URL) {
        cleanupImportedAlbumDirectory()
        holdSecurityScope(for: url)
        lastSource = .folder(url)
        refreshUsbStatus()
        let scannerRef = scanner
        runScan { progress in
            try scannerRef.scanFolder(url: url, securityScoped: false, onProgress: progress)
        }
    }

    public func scanDocument(url: URL) {
        cleanupImportedAlbumDirectory()
        holdSecurityScope(for: url)
        lastSource = .singleFile(url)
        refreshUsbStatus()
        let scannerRef = scanner
        runScan { _ in
            try scannerRef.scanSingleFile(url: url, securityScoped: false)
        }
    }

    public func scanAlbumProviders(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        if running {
            showToast("正在合成视频，请稍候再选择")
            return
        }
        scanTask?.cancel()
        releaseSecurityScope()
        cleanupImportedAlbumDirectory()

        scanning = true
        scanMessage = "正在从相册导入 …"
        alertError = nil
        warnings = []

        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickedAlbumVideos", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        importedAlbumDirectory = sessionDir
        let scannerRef = scanner

        scanTask = Task {
            do {
                try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
                var copiedURLs: [URL] = []
                copiedURLs.reserveCapacity(providers.count)
                var usedNames: Set<String> = []

                for (index, provider) in providers.enumerated() {
                    try Task.checkCancellation()
                    if providers.count > 1 {
                        scanMessage = "正在从相册导入 \(index + 1)/\(providers.count) …"
                    }
                    let url = try await Self.copyVideoFromProvider(
                        provider,
                        to: sessionDir,
                        index: index,
                        usedNames: &usedNames
                    )
                    copiedURLs.append(url)
                }

                try Task.checkCancellation()
                let label: String? = copiedURLs.count == 1 ? nil : "相册 · \(copiedURLs.count) 个视频"
                let result = try await Task.detached(priority: .userInitiated) {
                    try scannerRef.scanFiles(urls: copiedURLs, securityScoped: false, sourceLabel: label)
                }.value

                guard !Task.isCancelled else {
                    scanning = false
                    return
                }
                lastSource = .albumFiles(copiedURLs, label)
                applyScan(result)
            } catch is CancellationError {
                scanning = false
                scanMessage = ""
            } catch {
                scanning = false
                scanMessage = ""
                alertError = "导入相册视频失败: \(error.localizedDescription)"
            }
        }
    }

    public func rescan() {
        guard let lastSource else {
            showToast("请先选择 U 盘目录或视频文件")
            return
        }
        switch lastSource {
        case .folder(let url):
            let scannerRef = scanner
            runScan { progress in
                try scannerRef.scanFolder(url: url, securityScoped: false, onProgress: progress)
            }
        case .singleFile(let url):
            let scannerRef = scanner
            runScan { _ in
                try scannerRef.scanSingleFile(url: url, securityScoped: false)
            }
        case .albumFiles(let urls, let label):
            let scannerRef = scanner
            runScan { _ in
                try scannerRef.scanFiles(urls: urls, securityScoped: false, sourceLabel: label)
            }
        }
    }

    private func runScan(block: @escaping @Sendable (@escaping @Sendable (String) -> Void) throws -> ScanResult) {
        if running {
            showToast("正在合成视频，请稍候再扫描")
            return
        }
        scanTask?.cancel()
        scanning = true
        scanMessage = "正在扫描 …"
        alertError = nil
        warnings = []

        let progressHandler: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.scanMessage = msg
            }
        }

        scanTask = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try block(progressHandler)
                }.value
                guard !Task.isCancelled else {
                    scanning = false
                    return
                }
                applyScan(result)
            } catch is CancellationError {
                scanning = false
            } catch {
                scanning = false
                scanMessage = ""
                alertError = "扫描失败: \(error.localizedDescription)"
            }
        }
    }

    private func applyScan(_ result: ScanResult) {
        let preselected = Set(result.groups.first?.files.map(\.id) ?? [])
        scanning = false
        scanMessage = ""
        groups = result.groups
        selected = preselected
        sourceLabel = result.sourceLabel
        hasChosenSource = true
        warnings = result.warnings
        results = []
        failures = []
        doneVisible = false
        progress = 0
        status = result.fileCount == 0
            ? "没有找到视频"
            : "找到 \(result.groups.count) 个片段 / \(result.fileCount) 个视频"
        alertError = nil
        refreshUsbStatus()

        if let warning = result.warnings.first {
            showToast(warning)
        }
    }

    // MARK: - Selection

    public func toggleFile(_ fileId: String) {
        if selected.contains(fileId) {
            selected.remove(fileId)
        } else {
            selected.insert(fileId)
        }
        if !selected.isEmpty { doneVisible = false }
    }

    public func setFileSelected(_ fileId: String, isSelected: Bool) {
        if isSelected {
            selected.insert(fileId)
        } else {
            selected.remove(fileId)
        }
        if !selected.isEmpty { doneVisible = false }
    }

    public func setGroupSelected(_ groupId: String, isSelected: Bool) {
        guard let group = groups.first(where: { $0.id == groupId }) else { return }
        for file in group.files {
            if isSelected {
                selected.insert(file.id)
            } else {
                selected.remove(file.id)
            }
        }
        if !selected.isEmpty { doneVisible = false }
    }

    public func selectAll(_ select: Bool) {
        if select {
            selected = Set(groups.flatMap { $0.files.map(\.id) })
            if !selected.isEmpty { doneVisible = false }
        } else {
            selected = []
        }
    }

    // MARK: - Preview

    public func requestPreviewFor(fileId: String) {
        selected.insert(fileId)
        doneVisible = false
        requestPreview(preferredFileId: fileId)
    }

    public func requestPreview(preferredFileId: String? = nil) {
        let targetPair: (group: ClipGroup, file: ClipFile)?
        if let preferredFileId {
            targetPair = groups.lazy.compactMap { g in
                g.files.first(where: { $0.id == preferredFileId }).map { (group: g, file: $0) }
            }.first
        } else {
            targetPair = selectedFiles().first ?? groups.first.flatMap { g in
                g.files.first.map { (group: g, file: $0) }
            }
        }

        guard let pair = targetPair else {
            showToast("请先选择视频")
            return
        }
        guard !previewLoading else { return }

        let style = currentStyle
        let group = pair.group
        let file = pair.file
        previewLoading = true

        Task {
            let detail = style.showDetails
                ? OverlayText.detailLine(cameraLabel: TeslaNaming.cameraLabel(file.camera), eventInfo: group.eventInfo)
                : nil

            let cgImage = await PreviewComposer.compose(
                source: file.source,
                startEpochMillis: group.startEpochMillis,
                style: style,
                detailText: detail
            )

            previewLoading = false
            guard let cgImage else {
                alertError = "无法生成预览"
                return
            }

            let caption = "画面时间 \(OverlayText.firstLine(group.startEpochMillis + 1000, style: style)) · \(TeslaNaming.cameraLabel(file.camera))"
            preview = PreviewState(image: UIImage(cgImage: cgImage), caption: caption)
        }
    }

    // MARK: - Batch Transcode & Export

    public func generate() {
        guard !running else { return }
        let items = selectedFiles()
        guard !items.isEmpty else {
            showToast("请先勾选要处理的视频")
            return
        }

        let style = currentStyle
        let processorRef = processor

        running = true
        doneVisible = false
        progress = 0
        status = "准备合成 …"
        alertError = nil
        results = []
        failures = []

        workTask = Task {
            var exportedResults: [ExportResult] = []
            var itemFailures: [String] = []
            var lastProgressStep = -1

            do {
                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()

                    let group = item.group
                    let file = item.file
                    let cameraLabel = TeslaNaming.cameraLabel(file.camera)
                    let label = "\(cameraLabel) · \(TimeFormats.dateTime(group.startEpochMillis))"
                    status = "正在合成 \(index + 1)/\(items.count)：\(label)"

                    let tempFile = FileManager.default.temporaryDirectory
                        .appendingPathComponent("timestamp_\(Int(Date().timeIntervalSince1970 * 1000))_\(index).mp4")
                    defer {
                        if FileManager.default.fileExists(atPath: tempFile.path) {
                            try? FileManager.default.removeItem(at: tempFile)
                        }
                    }

                    let base = Float(index) / Float(items.count)
                    let step = 1.0 / Float(items.count)

                    do {
                        let detail = style.showDetails
                            ? OverlayText.detailLine(cameraLabel: cameraLabel, eventInfo: group.eventInfo)
                            : nil
                        let request = TranscodeRequest(
                            source: file.source,
                            outputURL: tempFile,
                            startEpochMillis: group.startEpochMillis,
                            style: style,
                            detailText: detail
                        )

                        let transcodeResult = try await Task.detached(priority: .userInitiated) {
                            try await processorRef.process(request) { fraction in
                                let overall = base + fraction * step
                                let bucket = Int(overall * 100.0)
                                Task { @MainActor in
                                    if bucket != lastProgressStep {
                                        lastProgressStep = bucket
                                        self.progress = overall
                                    }
                                }
                            }
                        }.value

                        let outSize = (try? FileManager.default.attributesOfItem(atPath: tempFile.path)[.size] as? NSNumber)?.int64Value ?? 0
                        let displayName = Self.outputName(group: group, file: file)
                        let exportedURL = try await PhotoLibraryExporter.export(
                            sourceURL: tempFile,
                            displayName: displayName
                        )

                        let exported = ExportResult(
                            url: exportedURL,
                            displayName: displayName,
                            durationMs: transcodeResult.durationMs,
                            sizeBytes: outSize,
                            startEpochMillis: group.startEpochMillis,
                            cameraLabel: cameraLabel
                        )
                        exportedResults.append(exported)
                        results = exportedResults
                    } catch let cancelled as TranscodeCancelledError {
                        throw cancelled
                    } catch is CancellationError {
                        throw TranscodeCancelledError()
                    } catch {
                        itemFailures.append("\(label)：\(error.localizedDescription)")
                    }
                }

                if exportedResults.isEmpty {
                    running = false
                    progress = 0
                    status = "合成失败"
                    failures = itemFailures
                    alertError = itemFailures.first ?? "没有生成视频"
                } else {
                    running = false
                    progress = 1.0
                    results = exportedResults
                    failures = itemFailures
                    doneVisible = true
                    status = itemFailures.isEmpty
                        ? "完成：\(exportedResults.count) 个视频已导出到相册 TeslaTimestamp"
                        : "完成 \(exportedResults.count) 个，失败 \(itemFailures.count) 个"
                    showResultsSheet = true
                }
            } catch is TranscodeCancelledError {
                running = false
                progress = 0
                status = "已取消"
                showToast("已取消")
            } catch is CancellationError {
                running = false
                progress = 0
                status = "已取消"
                showToast("已取消")
            } catch {
                running = false
                progress = 0
                status = "合成失败"
                alertError = error.localizedDescription
            }
        }
    }

    public func cancelWork() {
        processor.cancel()
        workTask?.cancel()
        status = "正在取消 …"
    }

    // MARK: - Playback & Share

    public func playLatestResult() {
        guard let latest = results.last else {
            showToast("没有可播放的结果")
            return
        }
        activePlayerItem = PlayerSheetItem(url: latest.url, title: latest.title)
    }

    public func playResult(_ result: ExportResult) {
        activePlayerItem = PlayerSheetItem(url: result.url, title: result.displayName)
    }

    public func shareResult(_ url: URL) {
        activeShareItem = ShareSheetItem(url: url)
    }

    public func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = text
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                toastMessage = nil
            }
        }
    }

    // MARK: - Helpers

    private func holdSecurityScope(for url: URL) {
        releaseSecurityScope()
        if url.startAccessingSecurityScopedResource() {
            activeSecurityScopedURL = url
        }
    }

    private func releaseSecurityScope() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    private func cleanupImportedAlbumDirectory() {
        if let dir = importedAlbumDirectory {
            try? FileManager.default.removeItem(at: dir)
            importedAlbumDirectory = nil
        }
    }

    private static func copyVideoFromProvider(
        _ provider: NSItemProvider,
        to directory: URL,
        index: Int,
        usedNames: inout Set<String>
    ) async throws -> URL {
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) {
            typeIdentifier = UTType.mpeg4Movie.identifier
        } else {
            typeIdentifier = UTType.movie.identifier
        }

        let suggestedBase = provider.suggestedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")

        let copiedResult: (url: URL, preferredName: String, sourceDate: Date?) = try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { tempURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: NSError(
                        domain: "TeslaTimestamp",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "无法读取所选相册视频"]
                    ))
                    return
                }
                do {
                    let ext = tempURL.pathExtension.isEmpty ? "mp4" : tempURL.pathExtension
                    let rawName: String
                    if let suggestedBase, !suggestedBase.isEmpty {
                        if (suggestedBase as NSString).pathExtension.isEmpty {
                            rawName = "\(suggestedBase).\(ext)"
                        } else {
                            rawName = suggestedBase
                        }
                    } else if !tempURL.lastPathComponent.isEmpty {
                        rawName = tempURL.lastPathComponent
                    } else {
                        rawName = "album_video_\(index + 1).\(ext)"
                    }

                    let sourceValues = try? tempURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let sourceDate = sourceValues?.creationDate ?? sourceValues?.contentModificationDate

                    // Copy synchronously before loadFileRepresentation cleans up tempURL.
                    let stagingURL = directory.appendingPathComponent("staged_\(index)_\(UUID().uuidString).\(ext)")
                    try FileManager.default.copyItem(at: tempURL, to: stagingURL)
                    continuation.resume(returning: (stagingURL, rawName, sourceDate))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Rename staged file to a unique display filename on the caller's actor.
        let preferredName = copiedResult.preferredName
        var candidate = preferredName
        var suffix = 2
        while usedNames.contains(candidate.lowercased()) {
            let stem = (preferredName as NSString).deletingPathExtension
            let fileExt = (preferredName as NSString).pathExtension
            candidate = fileExt.isEmpty ? "\(stem)_\(suffix)" : "\(stem)_\(suffix).\(fileExt)"
            suffix += 1
        }
        usedNames.insert(candidate.lowercased())

        let finalURL = directory.appendingPathComponent(candidate)
        try FileManager.default.moveItem(at: copiedResult.url, to: finalURL)

        // Preserve original recording timestamp from video metadata (or source file date) so
        // non-Tesla filenames still burn the authentic capture time.
        let asset = AVURLAsset(url: finalURL)
        let creationItem = try? await asset.load(.creationDate)
        let metadataDate = try? await creationItem?.load(.dateValue)
        if let effectiveDate = metadataDate ?? copiedResult.sourceDate {
            try? FileManager.default.setAttributes([.modificationDate: effectiveDate], ofItemAtPath: finalURL.path)
        }

        return finalURL
    }

    private static func outputName(group: ClipGroup, file: ClipFile) -> String {
        let stamp = TimeFormats.dateTime(group.startEpochMillis)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let camera = file.camera ?? "video"
        return "\(stamp)_\(camera)_timestamped.mp4"
    }
}
#endif
