import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import XCTest
#if canImport(TeslaTimestampCore)
@testable import TeslaTimestampCore
#else
@testable import TeslaTimestamp
#endif

final class TimestampTranscoderTests: XCTestCase {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private let startMs: Int64 = 1_714_537_800_000 // 2024-05-01 12:30:00 +08:00

    func testOrientAndScalePreservesTopLeftCornerAcrossIdentityAnd90DegreeRotation() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let srcCtx = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 200,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 200 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        // Fill blue everywhere, then paint bottom-left (0..40, 0..40 in bottom-up CG coords) pure red.
        // Under a 90° CW QuickTime rotation, bottom-left of sensor becomes top-left of upright portrait frame!
        srcCtx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        srcCtx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        srcCtx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        srcCtx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let srcCG = try XCTUnwrap(srcCtx.makeImage())

        // 90° CW QuickTime transform on 200x100 -> upright 100x200
        let transform90 = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 100, ty: 0)
        let oriented = TimestampTranscoder.orientAndScale(
            image: CIImage(cgImage: srcCG),
            preferredTransform: transform90,
            outputWidth: 100,
            outputHeight: 200
        )
        XCTAssertEqual(100, Int(oriented.extent.width.rounded()))
        XCTAssertEqual(200, Int(oriented.extent.height.rounded()))

        // Verify exact mathematical mapping of sensor bottom-left (5, 5) -> upright top-left (5, 195)
        let matrix = TimestampTranscoder.uprightTransform(
            srcWidth: 200,
            srcHeight: 100,
            preferredTransform: transform90,
            outputWidth: 100,
            outputHeight: 200
        )
        let mappedTopLeft = CGPoint(x: 5, y: 5).applying(matrix)
        XCTAssertEqual(5.0, mappedTopLeft.x, accuracy: 0.001)
        XCTAssertEqual(195.0, mappedTopLeft.y, accuracy: 0.001)

        // Also verify pixel color when Metal/IOSurface rendering is available in the host process
        let ciContext = CIContext(options: [.workingColorSpace: colorSpace])
        if let rendered = ciContext.createCGImage(oriented, from: CGRect(x: 0, y: 0, width: 100, height: 200)) {
            XCTAssertEqual(100, rendered.width)
            XCTAssertEqual(200, rendered.height)
            var pixel = [UInt8](repeating: 0, count: 4)
            let probeCtx = try XCTUnwrap(
                CGContext(
                    data: &pixel,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            probeCtx.draw(rendered, in: CGRect(x: -5, y: -195, width: 100, height: 200))
            XCTAssertGreaterThan(pixel[0], 200, "Expected red channel > 200 at top-left after 90° CW rotation")
            XCTAssertLessThan(pixel[2], 50, "Expected blue channel < 50 at top-left after 90° CW rotation")
        }
    }

    func testPreviewComposerFallbackRendersStyledOverlay() async throws {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing_\(UUID().uuidString).mp4")
        let source = MediaSource(url: missingURL)
        let style = OverlayStyle(position: .bottomRight, textScale: 1.4, showDate: true, showDetails: true)
        let composed = await PreviewComposer.compose(
            source: source,
            startEpochMillis: startMs,
            style: style,
            detailText: "前视 · 上海市 · 31.23040, 121.47370 · 哨兵事件",
            timeZone: shanghai
        )
        let image = try XCTUnwrap(composed)
        XCTAssertEqual(720, image.width)
        XCTAssertEqual(405, image.height)
    }

    func testTranscodesHW3VideoAndPreservesFrameCountAndPreview() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscodeTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputURL = tempDir.appendingPathComponent("2024-05-01_12-30-00-front.mp4")
        let outputURL = tempDir.appendingPathComponent("2024-05-01_12-30-00_front_timestamped.mp4")

        try await generateSyntheticVideo(
            at: inputURL,
            width: 640,
            height: 480,
            fps: 30,
            frameCount: 45,
            codec: .h264,
            preferredTransform: .identity,
            includeAudio: false
        )

        let source = MediaSource(url: inputURL, securityScopeRootURL: nil)
        let style = OverlayStyle(position: .topLeft, textScale: 1.0, showDate: true, showDetails: true)

        // 1. Verify WYSIWYG preview composer
        let preview = await PreviewComposer.compose(
            source: source,
            startEpochMillis: startMs,
            style: style,
            detailText: "前视 · 上海市 · 31.23040, 121.47370 · 手动保存",
            timeZone: shanghai
        )
        let previewImage = try XCTUnwrap(preview)
        XCTAssertEqual(720, previewImage.width)
        XCTAssertEqual(540, previewImage.height)

        // 2. Verify full GPU timestamp transcoding
        let processor = TimestampVideoProcessor()
        let request = TranscodeRequest(
            source: source,
            outputURL: outputURL,
            startEpochMillis: startMs,
            style: style,
            detailText: "前视 · 上海市 · 31.23040, 121.47370 · 手动保存",
            timeZone: shanghai
        )

        final class ProgressBox: @unchecked Sendable {
            private let lock = NSLock()
            var value: Float = 0
            func update(_ next: Float) {
                lock.lock()
                value = next
                lock.unlock()
            }
        }
        let progressBox = ProgressBox()
        let result = try await processor.process(request) { progress in
            progressBox.update(progress)
        }

        XCTAssertEqual(640, result.width)
        XCTAssertEqual(480, result.height)
        XCTAssertEqual(45, result.frameCount)
        XCTAssertEqual(1.0, progressBox.value, accuracy: 0.01)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let outAsset = AVURLAsset(url: outputURL)
        let outTracks = try await outAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(1, outTracks.count)
        let outSize = try await outTracks[0].load(.naturalSize)
        XCTAssertEqual(640, Int(outSize.width))
        XCTAssertEqual(480, Int(outSize.height))
    }

    func testTranscodesRotatedVideoWithAudioTrackAndSwapsDimensions() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RotatedTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputURL = tempDir.appendingPathComponent("rotated.mp4")
        let outputURL = tempDir.appendingPathComponent("rotated_timestamped.mp4")

        // 90° clockwise QuickTime transform for a 640x360 sensor -> upright 360x640
        let transform90 = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)
        try await generateSyntheticVideo(
            at: inputURL,
            width: 640,
            height: 360,
            fps: 30,
            frameCount: 30,
            codec: .h264,
            preferredTransform: transform90,
            includeAudio: true
        )

        let source = MediaSource(url: inputURL, securityScopeRootURL: nil)
        let processor = TimestampVideoProcessor()
        let request = TranscodeRequest(
            source: source,
            outputURL: outputURL,
            startEpochMillis: startMs,
            style: OverlayStyle(position: .bottomRight, textScale: 1.4, showDate: false, showDetails: false),
            detailText: nil,
            timeZone: shanghai
        )

        let result = try await processor.process(request)
        XCTAssertEqual(360, result.width)
        XCTAssertEqual(640, result.height)
        XCTAssertEqual(30, result.frameCount)

        let outAsset = AVURLAsset(url: outputURL)
        let audioTracks = try await outAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(1, audioTracks.count)
    }

    // MARK: - Synthetic MP4 Generator

    private func generateSyntheticVideo(
        at url: URL,
        width: Int,
        height: Int,
        fps: Int,
        frameCount: Int,
        codec: AVVideoCodecType,
        preferredTransform: CGAffineTransform,
        includeAudio: Bool
    ) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.transform = preferredTransform
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if includeAudio {
            let aSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            aIn.expectsMediaDataInRealTime = false
            if writer.canAdd(aIn) {
                writer.add(aIn)
                audioInput = aIn
            }
        }

        guard writer.startWriting() else {
            throw XCTSkip("AVAssetWriter unavailable in current sandbox environment: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        for frameIdx in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var pbOut: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbOut)
            } else {
                CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    width,
                    height,
                    kCVPixelFormatType_32BGRA,
                    [
                        kCVPixelBufferCGImageCompatibilityKey: true,
                        kCVPixelBufferCGBitmapContextCompatibilityKey: true
                    ] as CFDictionary,
                    &pbOut
                )
            }
            let pb = try XCTUnwrap(pbOut)

            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pb),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                // Draw distinct quadrant colors to exercise orientation
                ctx.setFillColor(CGColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1.0))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.setFillColor(CGColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1.0))
                ctx.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            let pts = CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(fps))
            XCTAssertTrue(adaptor.append(pb, withPresentationTime: pts))
        }
        videoInput.markAsFinished()

        if let aIn = audioInput {
            let sampleCount = 44_100
            var asbd = AudioStreamBasicDescription(
                mSampleRate: 44_100,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 2,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 16,
                mReserved: 0
            )
            var formatDesc: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDesc
            )
            if let formatDesc {
                var blockBuffer: CMBlockBuffer?
                let dataLength = sampleCount * 2
                CMBlockBufferCreateWithMemoryBlock(
                    allocator: kCFAllocatorDefault,
                    memoryBlock: nil,
                    blockLength: dataLength,
                    blockAllocator: kCFAllocatorDefault,
                    customBlockSource: nil,
                    offsetToData: 0,
                    dataLength: dataLength,
                    flags: kCMBlockBufferAssureMemoryNowFlag,
                    blockBufferOut: &blockBuffer
                )
                if let blockBuffer {
                    CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: dataLength)
                    var sampleBuffer: CMSampleBuffer?
                    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                        allocator: kCFAllocatorDefault,
                        dataBuffer: blockBuffer,
                        formatDescription: formatDesc,
                        sampleCount: sampleCount,
                        presentationTimeStamp: .zero,
                        packetDescriptions: nil,
                        sampleBufferOut: &sampleBuffer
                    )
                    if let sampleBuffer {
                        while !aIn.isReadyForMoreMediaData {
                            try await Task.sleep(nanoseconds: 2_000_000)
                        }
                        _ = aIn.append(sampleBuffer)
                    }
                }
            }
            aIn.markAsFinished()
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        XCTAssertEqual(.completed, writer.status)
    }
}
