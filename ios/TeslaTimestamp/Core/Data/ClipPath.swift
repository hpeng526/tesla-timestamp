import Foundation

public enum ClipCategory: String, Sendable, CaseIterable, Equatable {
    case recent = "RECENT"
    case saved = "SAVED"
    case sentry = "SENTRY"
    case unknown = "UNKNOWN"

    public var label: String {
        switch self {
        case .recent: return "近期片段"
        case .saved: return "已保存"
        case .sentry: return "哨兵模式"
        case .unknown: return "其他"
        }
    }
}

/// Everything needed to place a single MP4 file inside the TeslaCam folder tree.
public struct ClipIdentity: Sendable, Equatable {
    public let category: ClipCategory
    public let clipStartMillis: Int64
    public let camera: String?
    public let timestampFromName: Bool

    public init(
        category: ClipCategory,
        clipStartMillis: Int64,
        camera: String?,
        timestampFromName: Bool
    ) {
        self.category = category
        self.clipStartMillis = clipStartMillis
        self.camera = camera
        self.timestampFromName = timestampFromName
    }

    public var groupId: String {
        "\(category.rawValue)@\(clipStartMillis)"
    }
}

/// Turns a path relative to a TeslaCam root (or any folder) into a `ClipIdentity`.
///
/// Supported layouts, all relative paths:
///  - `TeslaCam/RecentClips/2024-05-01_12-30-00-front.mp4`
///  - `TeslaCam/SavedClips/2024-05-01_12-30-00/front.mp4`
///  - `TeslaCam/SentryClips/2024-05-01_12-30-00/event.json` (not an mp4 -> `nil`)
///  - anything else that still carries a Tesla timestamp in the file name
public enum ClipPathParser {

    private static let categoryNames: [String: ClipCategory] = [
        "recentclips": .recent,
        "savedclips": .saved,
        "sentryclips": .sentry
    ]

    public static func parse(
        _ relativePath: String,
        timeZone: TimeZone = .current
    ) -> ClipIdentity? {
        let normalized = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty else { return nil }

        let segments = normalized.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard let fileName = segments.last, TeslaNaming.isMp4(fileName) else {
            return nil
        }

        let directorySegments = Array(segments.dropLast())
        var category: ClipCategory = .unknown
        for segment in directorySegments {
            if let matched = categoryNames[segment.lowercased()] {
                category = matched
            }
        }

        // 1) Event clips: the parent directory carries the start time.
        for segment in directorySegments.reversed() {
            if let start = TeslaNaming.parseClipDirectory(segment, timeZone: timeZone) {
                return ClipIdentity(
                    category: category == .unknown ? .saved : category,
                    clipStartMillis: start,
                    camera: TeslaNaming.cameraOf(fileName) ?? TeslaNaming.baseName(fileName).lowercased(),
                    timestampFromName: true
                )
            }
        }

        // 2) Recent clips: the file itself carries the start time.
        guard let start = TeslaNaming.parseTimestamp(fileName, timeZone: timeZone) else {
            return nil
        }
        return ClipIdentity(
            category: category == .unknown ? .recent : category,
            clipStartMillis: start,
            camera: TeslaNaming.cameraOf(fileName),
            timestampFromName: true
        )
    }
}
