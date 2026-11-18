import Foundation

/// One MP4 inside a clip group (`front` / `back` / `left_repeater` / `left_pillar` ...).
public struct ClipFile: Sendable, Identifiable, Equatable {
    public let id: String
    public let camera: String?
    public let source: MediaSource
    public let sizeBytes: Int64

    public init(id: String, camera: String?, source: MediaSource, sizeBytes: Int64) {
        self.id = id
        self.camera = camera
        self.source = source
        self.sizeBytes = sizeBytes
    }

    public var displayName: String {
        source.displayName
    }
}

/// All camera files that belong to one Tesla minute. RecentClips groups hold one file per camera,
/// SavedClips / SentryClips groups hold up to 4 or 6 (plus `event.json` metadata).
public struct ClipGroup: Sendable, Identifiable, Equatable {
    public let id: String
    public let category: ClipCategory
    public let startEpochMillis: Int64
    public let eventInfo: TeslaEventInfo?
    public let files: [ClipFile]

    public init(
        id: String,
        category: ClipCategory,
        startEpochMillis: Int64,
        eventInfo: TeslaEventInfo?,
        files: [ClipFile]
    ) {
        self.id = id
        self.category = category
        self.startEpochMillis = startEpochMillis
        self.eventInfo = eventInfo
        self.files = files
    }

    public var title: String {
        TimeFormats.dateTime(startEpochMillis)
    }

    public var totalSizeBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }

    public var subtitle: String {
        var parts: [String] = [
            category.label,
            "\(files.count) 个视频"
        ]
        if let reason = eventInfo?.reasonLabel() {
            parts.append(reason)
        }
        return parts.joined(separator: " · ")
    }

    public var cardMetadata: String {
        var parts: [String] = [
            category.label,
            "\(files.count) 个视频",
            TimeFormats.fileSize(totalSizeBytes)
        ]
        if let reason = eventInfo?.reasonLabel() {
            parts.append(reason)
        }
        return parts.joined(separator: " · ")
    }
}
