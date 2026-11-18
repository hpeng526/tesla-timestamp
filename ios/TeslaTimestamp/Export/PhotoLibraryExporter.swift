#if canImport(Photos) && canImport(UIKit)
import Foundation
import Photos

public enum PhotoExportError: LocalizedError {
    case sourceMissing
    case permissionDenied
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "导出源文件不存在"
        case .permissionDenied:
            return "未获得相册写入权限，请在“设置 → 隐私与安全性 → 照片”中允许访问"
        case .saveFailed(let reason):
            return "保存到系统相册失败: \(reason)"
        }
    }
}

/// Saves a finished timestamped MP4 into the iOS Photos library (inside the `"TeslaTimestamp"`
/// album whenever album access is granted) and retains a clean local copy for instant playback & sharing.
public enum PhotoLibraryExporter {

    public static let albumName = "TeslaTimestamp"

    public static func export(sourceURL: URL, displayName: String) async throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw PhotoExportError.sourceMissing
        }

        // 1. Copy to named local export file so Share Sheet & AVPlayer use the exact Tesla filename.
        let exportsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TeslaTimestampExports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        let localExportURL = uniqueFileURL(in: exportsDir, fileName: displayName)
        try FileManager.default.copyItem(at: sourceURL, to: localExportURL)

        // 2. Save to iOS Photos Library.
        let readWriteStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if readWriteStatus == .authorized || readWriteStatus == .limited {
            try await saveVideoToPhotos(fileURL: localExportURL, tryAlbum: readWriteStatus == .authorized)
            return localExportURL
        }

        let addOnlyStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard addOnlyStatus == .authorized || addOnlyStatus == .limited else {
            throw PhotoExportError.permissionDenied
        }

        try await saveVideoToPhotos(fileURL: localExportURL, tryAlbum: false)
        return localExportURL
    }

    private static func saveVideoToPhotos(fileURL: URL, tryAlbum: Bool) async throws {
        let album: PHAssetCollection? = tryAlbum ? (try? await findOrCreateAlbum(named: albumName)) : nil

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL) else {
                    return
                }
                if let album,
                   let placeholder = assetRequest.placeholderForCreatedAsset,
                   let albumChange = PHAssetCollectionChangeRequest(for: album) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: PhotoExportError.saveFailed(error?.localizedDescription ?? "未知错误")
                    )
                }
            })
        }
    }

    private static func findOrCreateAlbum(named title: String) async throws -> PHAssetCollection? {
        if let existing = fetchAlbum(named: title) {
            return existing
        }

        var createdLocalIdentifier: String?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                createdLocalIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoExportError.saveFailed("无法创建相簿"))
                }
            })
        }

        guard let id = createdLocalIdentifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private static func fetchAlbum(named title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }

    private static func uniqueFileURL(in directory: URL, fileName: String) -> URL {
        var candidate = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let nsName = fileName as NSString
        let stem = nsName.deletingPathExtension
        let ext = nsName.pathExtension.isEmpty ? "mp4" : nsName.pathExtension
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)_\(index).\(ext)")
            index += 1
        }
        return candidate
    }
}
#endif
