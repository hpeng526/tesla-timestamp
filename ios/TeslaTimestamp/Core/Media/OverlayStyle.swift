import Foundation

public enum OverlayPosition: String, Sendable, CaseIterable, Equatable {
    case topLeft = "TOP_LEFT"
    case topRight = "TOP_RIGHT"
    case bottomLeft = "BOTTOM_LEFT"
    case bottomRight = "BOTTOM_RIGHT"

    public var label: String {
        switch self {
        case .topLeft: return "左上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        case .bottomRight: return "右下"
        }
    }
}

/// How the burned-in timestamp looks. Sizes are fractions of the video height so the result looks
/// identical at every resolution, mirroring the reference script (`fontsize=50` at 1080p ≈ 5%).
public struct OverlayStyle: Sendable, Equatable {
    public static let baseTextFraction: Float = 0.055
    public static let sizePresets: [Float] = [0.7, 1.0, 1.4]
    public static let sizeLabels: [String] = ["小", "中", "大"]

    public var position: OverlayPosition
    public var textScale: Float
    public var showDate: Bool
    public var showDetails: Bool
    public var boxAlpha: Float
    public var marginFraction: Float

    public init(
        position: OverlayPosition = .topLeft,
        textScale: Float = 1.0,
        showDate: Bool = true,
        showDetails: Bool = false,
        boxAlpha: Float = 0.5,
        marginFraction: Float = 0.02
    ) {
        self.position = position
        self.textScale = textScale
        self.showDate = showDate
        self.showDetails = showDetails
        self.boxAlpha = boxAlpha
        self.marginFraction = marginFraction
    }

    public var textFraction: Float {
        Self.baseTextFraction * textScale
    }
}

/// Formats the overlay lines for a given frame wall-clock time.
public enum OverlayText {

    public static func timeLine(_ epochMillis: Int64, timeZone: TimeZone = .current) -> String {
        TimeFormats.dateTime(epochMillis, timeZone: timeZone)
    }

    public static func firstLine(
        _ epochMillis: Int64,
        style: OverlayStyle,
        timeZone: TimeZone = .current
    ) -> String {
        if style.showDate {
            return TimeFormats.dateTime(epochMillis, timeZone: timeZone)
        } else {
            return TimeFormats.clock(epochMillis, timeZone: timeZone)
        }
    }

    /// Optional second line with camera / event metadata, mirroring the Android app and Windows script.
    public static func detailLine(
        cameraLabel: String?,
        eventInfo: TeslaEventInfo?
    ) -> String? {
        var parts: [String] = []
        if let cameraLabel = cameraLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cameraLabel.isEmpty {
            parts.append(cameraLabel)
        }
        if let city = eventInfo?.city?.trimmingCharacters(in: .whitespacesAndNewlines),
           !city.isEmpty {
            parts.append(city)
        }
        if let lat = eventInfo?.estLat, let lon = eventInfo?.estLon {
            parts.append(
                String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), lat, lon)
            )
        }
        if let reason = eventInfo?.reasonLabel() {
            parts.append(reason)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
