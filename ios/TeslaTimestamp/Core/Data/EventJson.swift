import Foundation

/// Minimal reader for the `event.json` file Tesla writes inside SavedClips / SentryClips folders.
public struct TeslaEventInfo: Sendable, Equatable {
    public let timestampIso: String?
    public let city: String?
    public let estLat: Double?
    public let estLon: Double?
    public let reason: String?
    public let camera: String?

    public init(
        timestampIso: String? = nil,
        city: String? = nil,
        estLat: Double? = nil,
        estLon: Double? = nil,
        reason: String? = nil,
        camera: String? = nil
    ) {
        self.timestampIso = timestampIso
        self.city = city
        self.estLat = estLat
        self.estLon = estLon
        self.reason = reason
        self.camera = camera
    }

    public func referenceLine() -> String? {
        var parts: [String] = []
        if let reason = reasonLabel() {
            parts.append(reason)
        }
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            parts.append(city)
        }
        if let lat = estLat, let lon = estLon {
            parts.append(String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), lat, lon))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public func reasonLabel() -> String? {
        guard let reason, !reason.isEmpty else { return nil }
        switch reason.lowercased() {
        case "sentry_aware_object_detection":
            return "哨兵事件"
        case "user_interaction_dashcam_icon_tapped",
             "user_interaction_dashcam_panel_save",
             "user_interaction_dashcam_launcher_action_tapped":
            return "手动保存"
        case "user_interaction_honk":
            return "鸣笛保存"
        case "sentry_aware_accel_v2":
            return "碰撞事件"
        case "saved_clip":
            return "已保存"
        default:
            return reason
        }
    }

    public static func parse(_ raw: String) -> TeslaEventInfo {
        if let data = raw.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return TeslaEventInfo(
                timestampIso: cleanString(dict["timestamp"]),
                city: cleanString(dict["city"]),
                estLat: cleanDouble(dict["est_lat"]),
                estLon: cleanDouble(dict["est_lon"]),
                reason: cleanString(dict["reason"]),
                camera: cleanString(dict["camera"])
            )
        }

        // Tolerant fallback when event.json has trailing commas or minor formatting quirks.
        return TeslaEventInfo(
            timestampIso: regexStringField(raw, name: "timestamp"),
            city: regexStringField(raw, name: "city"),
            estLat: regexDoubleField(raw, name: "est_lat"),
            estLon: regexDoubleField(raw, name: "est_lon"),
            reason: regexStringField(raw, name: "reason"),
            camera: regexStringField(raw, name: "camera")
        )
    }

    private static func cleanString(_ value: Any?) -> String? {
        if let str = value as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.isEmpty || trimmed == "null") ? nil : str
        }
        if let num = value as? NSNumber {
            return num.stringValue
        }
        return nil
    }

    private static func cleanDouble(_ value: Any?) -> Double? {
        if let num = value as? Double {
            return num.isFinite ? num : nil
        }
        if let num = value as? NSNumber {
            let d = num.doubleValue
            return d.isFinite ? d : nil
        }
        if let str = value as? String {
            return Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func regexStringField(_ raw: String, name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\"\(escaped)\"[ \\t\\r\\n]*:[ \\t\\r\\n]*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              let groupRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        let value = String(raw[groupRange])
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || trimmed == "null") ? nil : value
    }

    private static func regexDoubleField(_ raw: String, name: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\"\(escaped)\"[ \\t\\r\\n]*:[ \\t\\r\\n]*\"?(-?[0-9]+(?:\\.[0-9]+)?)\"?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              let groupRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        return Double(raw[groupRange])
    }
}
