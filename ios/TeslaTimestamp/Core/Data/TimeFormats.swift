import Foundation

/// Small formatting helpers shared by the UI and the overlay renderer.
public enum TimeFormats {

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func dateTime(_ epochMillis: Int64, timeZone: TimeZone = .current) -> String {
        let seconds = Double(epochMillis) / 1000.0
        // Truncate sub-second millis downward to match Instant.ofEpochMilli formatting in Java/Kotlin.
        let flooredSeconds = floor(seconds)
        let date = Date(timeIntervalSince1970: flooredSeconds)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            locale: posixLocale,
            c.year ?? 1970,
            c.month ?? 1,
            c.day ?? 1,
            c.hour ?? 0,
            c.minute ?? 0,
            c.second ?? 0
        )
    }

    public static func date(_ epochMillis: Int64, timeZone: TimeZone = .current) -> String {
        let full = dateTime(epochMillis, timeZone: timeZone)
        return String(full.prefix(10))
    }

    public static func clock(_ epochMillis: Int64, timeZone: TimeZone = .current) -> String {
        let full = dateTime(epochMillis, timeZone: timeZone)
        return String(full.suffix(8))
    }

    public static func fileSize(_ bytes: Int64) -> String {
        if bytes <= 0 { return "-" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 {
            return String(format: "%.0f KB", locale: posixLocale, Double(bytes) / 1024.0)
        }
        if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", locale: posixLocale, Double(bytes) / (1024.0 * 1024.0))
        }
        return String(format: "%.2f GB", locale: posixLocale, Double(bytes) / (1024.0 * 1024.0 * 1024.0))
    }

    public static func duration(_ seconds: Int64) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", locale: posixLocale, hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", locale: posixLocale, minutes, secs)
        }
    }
}
