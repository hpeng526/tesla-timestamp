import CoreGraphics
import CoreText
import Foundation

/// Renders the timestamp into an ARGB/BGRA `CGImage` the same way the reference ffmpeg filter and
/// Android app do: white bold text on a semi-transparent black box (`box=1:boxcolor=black@0.5`).
public enum OverlayBitmapFactory {

    public static func create(
        lines: [String],
        textSizePx: CGFloat,
        style: OverlayStyle
    ) -> CGImage? {
        let safeLines = lines.isEmpty ? [""] : lines
        let clampedFontSize = max(8.0, textSizePx)
        let font = makeBoldSystemFont(size: clampedFontSize)

        let padding = max(2, Int((clampedFontSize * 0.30).rounded(.down)))
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = max(0, CTFontGetLeading(font))
        let lineHeight = ascent + descent + leading
        let lineSpacing = max(1.0, clampedFontSize * 0.10)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let whiteColor = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 1.0])!

        var ctLines: [CTLine] = []
        ctLines.reserveCapacity(safeLines.count)
        var maxTextWidth: CGFloat = 0

        for line in safeLines {
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: whiteColor
            ]
            let attributed = CFAttributedStringCreate(
                kCFAllocatorDefault,
                line as CFString,
                attributes as CFDictionary
            )!
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            maxTextWidth = max(maxTextWidth, lineWidth)
            ctLines.append(ctLine)
        }

        let width = max(1, Int(ceil(maxTextWidth)) + padding * 2)
        let totalTextHeight = lineHeight * CGFloat(safeLines.count) +
            lineSpacing * CGFloat(max(0, safeLines.count - 1))
        let height = max(1, Int(ceil(totalTextHeight)) + padding * 2)

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)

        let clampedAlpha = CGFloat(min(1.0, max(0.0, style.boxAlpha)))
        let boxColor = CGColor(colorSpace: colorSpace, components: [0.0, 0.0, 0.0, clampedAlpha])!
        context.setFillColor(boxColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // CoreGraphics origin (0, 0) is bottom-left; line 0 sits near the top of the box.
        context.textMatrix = .identity
        for (index, ctLine) in ctLines.enumerated() {
            let baselineY = CGFloat(height - padding) - ascent - CGFloat(index) * (lineHeight + lineSpacing)
            context.textPosition = CGPoint(x: CGFloat(padding), y: baselineY)
            CTLineDraw(ctLine, context)
        }

        return context.makeImage()
    }

    /// Computes bottom-left origin coordinates `(x, y)` inside an image of `(canvasWidth × canvasHeight)`.
    public static func originInBottomUpCanvas(
        canvasWidth: Int,
        canvasHeight: Int,
        overlayWidth: Int,
        overlayHeight: Int,
        minMargin: Int,
        style: OverlayStyle
    ) -> (x: Int, y: Int) {
        let margin = max(minMargin, Int(CGFloat(canvasHeight) * CGFloat(style.marginFraction)))
        let x: Int
        switch style.position {
        case .topLeft, .bottomLeft:
            x = margin
        case .topRight, .bottomRight:
            x = max(margin, canvasWidth - margin - overlayWidth)
        }

        let y: Int
        switch style.position {
        case .topLeft, .topRight:
            y = max(margin, canvasHeight - margin - overlayHeight)
        case .bottomLeft, .bottomRight:
            y = margin
        }
        return (x, y)
    }

    private static func makeBoldSystemFont(size: CGFloat) -> CTFont {
        if let uiFont = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, "zh-Hans" as CFString) {
            return uiFont
        }
        return CTFontCreateWithName("PingFangSC-Semibold" as CFString, size, nil)
    }
}
