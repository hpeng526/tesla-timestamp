import AVFoundation
import CoreGraphics
import CoreText
import Foundation

/// Renders a still preview of a clip at t = 1s exactly the way the encoder draws the overlay:
/// same text size fraction, same margins, same box opacity, and the same position presets.
public enum PreviewComposer {

    public static let previewWidth = 720
    public static let previewOffsetSeconds: Double = 1.0

    public static func buildLines(
        startEpochMillis: Int64,
        style: OverlayStyle,
        detailText: String?,
        timeZone: TimeZone = .current
    ) -> [String] {
        let offsetMs = Int64(previewOffsetSeconds * 1000.0)
        let first = OverlayText.firstLine(
            startEpochMillis + offsetMs,
            style: style,
            timeZone: timeZone
        )
        let details = style.showDetails ? detailText : nil
        if let details = details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            return [first, details]
        }
        return [first]
    }

    public static func compose(
        source: MediaSource,
        startEpochMillis: Int64,
        style: OverlayStyle,
        detailText: String?,
        timeZone: TimeZone = .current
    ) async -> CGImage? {
        let rawFrame = await loadFrame(source: source) ?? makePlaceholder()
        guard let baseFrame = rawFrame else { return nil }

        let targetWidth = Self.previewWidth
        let sourceW = max(1, baseFrame.width)
        let sourceH = max(1, baseFrame.height)
        let scale = CGFloat(targetWidth) / CGFloat(sourceW)
        let targetHeight = max(1, Int((CGFloat(sourceH) * scale).rounded()))

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(baseFrame, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        let lines = buildLines(
            startEpochMillis: startEpochMillis,
            style: style,
            detailText: detailText,
            timeZone: timeZone
        )
        let textSizePx = max(10.0, CGFloat(targetHeight) * CGFloat(style.textFraction))
        if let overlay = OverlayBitmapFactory.create(lines: lines, textSizePx: textSizePx, style: style) {
            let origin = OverlayBitmapFactory.originInBottomUpCanvas(
                canvasWidth: targetWidth,
                canvasHeight: targetHeight,
                overlayWidth: overlay.width,
                overlayHeight: overlay.height,
                minMargin: 2,
                style: style
            )
            context.draw(
                overlay,
                in: CGRect(x: origin.x, y: origin.y, width: overlay.width, height: overlay.height)
            )
        }

        return context.makeImage()
    }

    public static func loadThumbnail(source: MediaSource, maxWidth: CGFloat = 320) async -> CGImage? {
        await source.withAsyncAccess { _ in
            let asset = source.makeAsset()
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)

            let targetTime = CMTime(seconds: previewOffsetSeconds, preferredTimescale: 600)
            if let image = try? await copyImage(generator: generator, at: targetTime) {
                return image
            }
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            return try? await copyImage(generator: generator, at: .zero)
        }
    }

    private static func loadFrame(source: MediaSource) async -> CGImage? {
        await source.withAsyncAccess { _ in
            let asset = source.makeAsset()
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

            let targetTime = CMTime(seconds: previewOffsetSeconds, preferredTimescale: 600)
            if let image = try? await copyImage(generator: generator, at: targetTime) {
                return image
            }
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            return try? await copyImage(generator: generator, at: .zero)
        }
    }

    private static func copyImage(generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
                if let cgImage, result == .succeeded {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(
                        throwing: error ?? NSError(domain: "PreviewComposer", code: -1, userInfo: nil)
                    )
                }
            }
        }
    }

    private static func makePlaceholder() -> CGImage? {
        let width = previewWidth
        let height = previewWidth * 9 / 16
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
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

        // #171A20 dark background
        let bg = CGColor(
            colorSpace: colorSpace,
            components: [23.0 / 255.0, 26.0 / 255.0, 32.0 / 255.0, 1.0]
        )!
        context.setFillColor(bg)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateUIFontForLanguage(.system, 24.0, "zh-Hans" as CFString)
            ?? CTFontCreateWithName("PingFangSC-Regular" as CFString, 24.0, nil)
        let white = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!
        let attr = CFAttributedStringCreate(
            kCFAllocatorDefault,
            "无法读取预览画面" as CFString,
            [kCTFontAttributeName: font, kCTForegroundColorAttributeName: white] as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attr)
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: (CGFloat(width) - textWidth) / 2.0,
            y: CGFloat(height) / 2.0 - 8.0
        )
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
