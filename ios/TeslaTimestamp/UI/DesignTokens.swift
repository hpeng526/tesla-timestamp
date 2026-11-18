#if canImport(UIKit)
import SwiftUI
import UIKit

enum TeslaColors {
    static let brandRed = Color(uiColor: UIColor(red: 0xE8 / 255.0, green: 0x21 / 255.0, blue: 0x27 / 255.0, alpha: 1))
    static let brandRedDark = Color(uiColor: dynamicColor(
        light: UIColor(red: 0x9C / 255.0, green: 0x0F / 255.0, blue: 0x13 / 255.0, alpha: 1),
        dark: UIColor(red: 0xB3 / 255.0, green: 0x16 / 255.0, blue: 0x1B / 255.0, alpha: 1)
    ))
    static let heroEnd = Color(uiColor: UIColor(red: 0x17 / 255.0, green: 0x1A / 255.0, blue: 0x20 / 255.0, alpha: 1))

    static let brandContainer = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xFC / 255.0, green: 0xE8 / 255.0, blue: 0xE9 / 255.0, alpha: 1),
        dark: UIColor(red: 0x3A / 255.0, green: 0x14 / 255.0, blue: 0x17 / 255.0, alpha: 1)
    ))
    static let onBrandContainer = Color(uiColor: dynamicColor(
        light: UIColor(red: 0x7A / 255.0, green: 0x11 / 255.0, blue: 0x16 / 255.0, alpha: 1),
        dark: UIColor(red: 0xFF / 255.0, green: 0xD9 / 255.0, blue: 0xDA / 255.0, alpha: 1)
    ))

    static let background = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xF4 / 255.0, green: 0xF5 / 255.0, blue: 0xF7 / 255.0, alpha: 1),
        dark: UIColor(red: 0x0D / 255.0, green: 0x10 / 255.0, blue: 0x15 / 255.0, alpha: 1)
    ))
    static let surface = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xFF / 255.0, green: 0xFF / 255.0, blue: 0xFF / 255.0, alpha: 1),
        dark: UIColor(red: 0x15 / 255.0, green: 0x1A / 255.0, blue: 0x21 / 255.0, alpha: 1)
    ))
    static let surfaceVariant = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xEF / 255.0, green: 0xF1 / 255.0, blue: 0xF4 / 255.0, alpha: 1),
        dark: UIColor(red: 0x1D / 255.0, green: 0x24 / 255.0, blue: 0x2D / 255.0, alpha: 1)
    ))
    static let onSurface = Color(uiColor: dynamicColor(
        light: UIColor(red: 0x13 / 255.0, green: 0x16 / 255.0, blue: 0x1B / 255.0, alpha: 1),
        dark: UIColor(red: 0xEC / 255.0, green: 0xEF / 255.0, blue: 0xF3 / 255.0, alpha: 1)
    ))
    static let onSurfaceVariant = Color(uiColor: dynamicColor(
        light: UIColor(red: 0x5B / 255.0, green: 0x63 / 255.0, blue: 0x6E / 255.0, alpha: 1),
        dark: UIColor(red: 0x9A / 255.0, green: 0xA4 / 255.0, blue: 0xB0 / 255.0, alpha: 1)
    ))
    static let outline = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xDC / 255.0, green: 0xE0 / 255.0, blue: 0xE6 / 255.0, alpha: 1),
        dark: UIColor(red: 0x2A / 255.0, green: 0x32 / 255.0, blue: 0x3C / 255.0, alpha: 1)
    ))
    static let success = Color(uiColor: dynamicColor(
        light: UIColor(red: 0x1F / 255.0, green: 0x8E / 255.0, blue: 0x3E / 255.0, alpha: 1),
        dark: UIColor(red: 0x4C / 255.0, green: 0xC2 / 255.0, blue: 0x6A / 255.0, alpha: 1)
    ))
    static let warning = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xB2 / 255.0, green: 0x6A / 255.0, blue: 0x00 / 255.0, alpha: 1),
        dark: UIColor(red: 0xE0 / 255.0, green: 0xA6 / 255.0, blue: 0x4B / 255.0, alpha: 1)
    ))
    static let danger = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xC6 / 255.0, green: 0x28 / 255.0, blue: 0x28 / 255.0, alpha: 1),
        dark: UIColor(red: 0xFF / 255.0, green: 0x6B / 255.0, blue: 0x6B / 255.0, alpha: 1)
    ))
    static let thumbnailPlaceholder = Color(uiColor: dynamicColor(
        light: UIColor(red: 0xE6 / 255.0, green: 0xE9 / 255.0, blue: 0xEE / 255.0, alpha: 1),
        dark: UIColor(red: 0x23 / 255.0, green: 0x2A / 255.0, blue: 0x33 / 255.0, alpha: 1)
    ))
    static let teslaDark = Color(uiColor: dynamicColor(
        light: UIColor(red: 0x17 / 255.0, green: 0x1A / 255.0, blue: 0x20 / 255.0, alpha: 1),
        dark: UIColor(red: 0x05 / 255.0, green: 0x07 / 255.0, blue: 0x0A / 255.0, alpha: 1)
    ))

    private static func dynamicColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

enum Haptics {
    @MainActor
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
#endif
