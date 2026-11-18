import Foundation

/// Pure helpers that understand the naming convention used by Tesla dashcam clips.
///
/// Tesla writes every camera into its own MP4 file:
///  - RecentClips: `"2024-05-01_12-30-00-front.mp4"`
///  - SavedClips / SentryClips: `"<clip dir>/front.mp4"` where the directory is `"2024-05-01_12-30-00"`.
///
/// The timestamp inside the name is the local wall-clock time of the car, therefore it is converted
/// with the device time zone - the same assumption the desktop reference script and Android app make.
public enum TeslaNaming {

    private static let timestampInNameRegex = try! NSRegularExpression(
        pattern: #"([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})"#
    )

    private static let clipDirRegex = try! NSRegularExpression(
        pattern: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$"#
    )

    private static let cameraFileRegex = try! NSRegularExpression(
        pattern: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}-(.+)\.mp4$"#,
        options: [.caseInsensitive]
    )

    private static let plainMp4Regex = try! NSRegularExpression(
        pattern: #"^(.+)\.mp4$"#,
        options: [.caseInsensitive]
    )

    public static func isMp4(_ fileName: String) -> Bool {
        fileName.lowercased().hasSuffix(".mp4") && fileName.count > 4
    }

    public static func baseName(_ fileName: String) -> String {
        if fileName.lowercased().hasSuffix(".mp4") {
            return String(fileName.dropLast(4))
        }
        return fileName
    }

    public static func isClipDirectoryName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return clipDirRegex.firstMatch(in: name, options: [], range: range) != nil
    }

    /// Parses `"2024-05-01_12-30-00"` (optionally followed by more text) into epoch milliseconds.
    public static func parseTimestamp(_ name: String, timeZone: TimeZone = .current) -> Int64? {
        let base = baseName(name)
        let range = NSRange(base.startIndex..<base.endIndex, in: base)
        guard let match = timestampInNameRegex.firstMatch(in: base, options: [], range: range) else {
            return nil
        }
        return toEpochMillis(match: match, in: base, timeZone: timeZone)
    }

    /// Epoch millis of a clip directory name, or `nil` when it is not a Tesla clip directory.
    public static func parseClipDirectory(_ name: String, timeZone: TimeZone = .current) -> Int64? {
        guard isClipDirectoryName(name) else { return nil }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = timestampInNameRegex.firstMatch(in: name, options: [], range: range) else {
            return nil
        }
        return toEpochMillis(match: match, in: name, timeZone: timeZone)
    }

    /// Camera identifier for a clip file: `"2024-05-01_12-30-00-left_repeater.mp4"` -> `"left_repeater"`,
    /// `"front.mp4"` -> `"front"`. Returns `nil` when no camera can be derived.
    public static func cameraOf(_ fileName: String) -> String? {
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        if let match = cameraFileRegex.firstMatch(in: fileName, options: [], range: range),
           let groupRange = Range(match.range(at: 1), in: fileName) {
            return fileName[groupRange].lowercased()
        }
        if let match = plainMp4Regex.firstMatch(in: fileName, options: [], range: range),
           let groupRange = Range(match.range(at: 1), in: fileName) {
            return fileName[groupRange].lowercased()
        }
        return nil
    }

    /// Chinese label for a Tesla camera identifier.
    public static func cameraLabel(_ camera: String?) -> String {
        guard let camera, !camera.isEmpty else { return "视频" }
        switch camera.lowercased() {
        case "front": return "前视"
        case "back": return "后视"
        case "left_repeater": return "左后"
        case "right_repeater": return "右后"
        case "left_pillar": return "左柱"
        case "right_pillar": return "右柱"
        default: return camera
        }
    }

    private static func toEpochMillis(
        match: NSTextCheckingResult,
        in source: String,
        timeZone: TimeZone
    ) -> Int64? {
        guard match.numberOfRanges >= 7 else { return nil }
        var numbers: [Int] = []
        numbers.reserveCapacity(6)
        for idx in 1...6 {
            guard let range = Range(match.range(at: idx), in: source),
                  let value = Int(source[range]) else {
                return nil
            }
            numbers.append(value)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = numbers[0]
        components.month = numbers[1]
        components.day = numbers[2]
        components.hour = numbers[3]
        components.minute = numbers[4]
        components.second = numbers[5]

        guard components.isValidDate(in: calendar),
              let date = calendar.date(from: components) else {
            return nil
        }
        return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    }
}
