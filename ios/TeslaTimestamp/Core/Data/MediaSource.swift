import AVFoundation
import Foundation

/// A readable MP4 file. TeslaCam clips on iOS can come from a security-scoped folder/file picked
/// in the Files app (USB OTG thumb drive, SD card reader, iCloud Drive) or a local sandbox path.
public struct MediaSource: Sendable, Hashable {
    public let url: URL
    public let displayName: String
    public let securityScopeRootURL: URL?

    public init(url: URL, displayName: String? = nil, securityScopeRootURL: URL? = nil) {
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.securityScopeRootURL = securityScopeRootURL
    }

    public var key: String {
        url.standardizedFileURL.path
    }

    /// Executes `body` while ensuring security-scoped resource access is active if required.
    public func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let rootStarted = securityScopeRootURL?.startAccessingSecurityScopedResource() ?? false
        let fileStarted = (securityScopeRootURL == nil) ? url.startAccessingSecurityScopedResource() : false
        defer {
            if fileStarted { url.stopAccessingSecurityScopedResource() }
            if rootStarted { securityScopeRootURL?.stopAccessingSecurityScopedResource() }
        }
        return try body(url)
    }

    /// Async variant of `withAccess` for AVFoundation async loading and transcoding.
    public func withAsyncAccess<T>(_ body: (URL) async throws -> T) async rethrows -> T {
        let rootStarted = securityScopeRootURL?.startAccessingSecurityScopedResource() ?? false
        let fileStarted = (securityScopeRootURL == nil) ? url.startAccessingSecurityScopedResource() : false
        defer {
            if fileStarted { url.stopAccessingSecurityScopedResource() }
            if rootStarted { securityScopeRootURL?.stopAccessingSecurityScopedResource() }
        }
        return try await body(url)
    }

    public func sizeBytes() -> Int64 {
        withAccess { targetURL in
            if let values = try? targetURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                return Int64(size)
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
               let size = attrs[.size] as? NSNumber {
                return size.int64Value
            }
            return 0
        }
    }

    public func lastModifiedMillis() -> Int64 {
        withAccess { targetURL in
            if let values = try? targetURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate {
                return Int64(date.timeIntervalSince1970 * 1000.0)
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
               let date = attrs[.modificationDate] as? Date {
                return Int64(date.timeIntervalSince1970 * 1000.0)
            }
            return 0
        }
    }

    public func makeAsset() -> AVURLAsset {
        AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    }
}
