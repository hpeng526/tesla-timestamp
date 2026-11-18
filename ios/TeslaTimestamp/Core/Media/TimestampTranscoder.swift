import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal

public struct TranscodeError: LocalizedError, Sendable {
    public let message: String
    public let underlying: Error?

    public init(_ message: String, underlying: Error? = nil) {
        self.message = message
        self.underlying = underlying
    }

    public var errorDescription: String? { message }
}

public struct TranscodeCancelledError: LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "已取消" }
}

public struct TranscodeRequest: Sendable {
    public let source: MediaSource
    public let outputURL: URL
    public let startEpochMillis: Int64
    public let style: OverlayStyle
    public let detailText: String?
    public let timeZone: TimeZone

    public init(
        source: MediaSource,
        outputURL: URL,
        startEpochMillis: Int64,
        style: OverlayStyle,
        detailText: String?,
        timeZone: TimeZone = .current
    ) {
        self.source = source
        self.outputURL = outputURL
        self.startEpochMillis = startEpochMillis
        self.style = style
        self.detailText = detailText
        self.timeZone = timeZone
    }
}

public struct TranscodeResult: Sendable, Equatable {
    public let outputURL: URL
    public let width: Int
    public let height: Int
    public let durationMs: Int64
    public let frameCount: Int64

    public init(outputURL: URL, width: Int, height: Int, durationMs: Int64, frameCount: Int64) {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.frameCount = frameCount
    }
}

/// Thread-safe cancellation state shared between caller and transcoding queues.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }
}

/// Burns a running timestamp into a Tesla dashcam clip using Apple's native hardware pipeline:
///
///   `AVAssetReader` (VideoToolbox H.264/HEVC decode)
///   -> `CIContext` (Metal GPU frame transform + cached per-second timestamp overlay composite)
///   -> `AVAssetWriter` (VideoToolbox H.264 hardware encode + compressed AAC audio passthrough).
final class TimestampTranscoder: @unchecked Sendable {

    private let request: TranscodeRequest
    private let cancelFlag = CancellationFlag()

    init(request: TranscodeRequest) {
        self.request = request
    }

    func cancel() {
        cancelFlag.cancel()
    }

    func transcode(onProgress: @escaping @Sendable (Float) -> Void) async throws -> TranscodeResult {
        try await request.source.withAsyncAccess { _ in
            try await runPipeline(onProgress: onProgress)
        }
    }

    private func runPipeline(onProgress: @escaping @Sendable (Float) -> Void) async throws -> TranscodeResult {
        if cancelFlag.isCancelled {
            throw TranscodeCancelledError()
        }

        let asset = request.source.makeAsset()
        let isReadable: Bool
        do {
            isReadable = try await asset.load(.isReadable)
        } catch {
            throw TranscodeError("无法读取视频文件: \(request.source.displayName)", underlying: error)
        }
        guard isReadable else {
            throw TranscodeError("无法读取视频文件: \(request.source.displayName)")
        }

        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw TranscodeError("读取视频轨道失败: \(request.source.displayName)", underlying: error)
        }
        guard let videoTrack = videoTracks.first else {
            throw TranscodeError("文件中没有视频轨道")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let assetDuration = try await asset.load(.duration)

        guard naturalSize.width > 0 && naturalSize.height > 0 else {
            throw TranscodeError("视频尺寸无效")
        }

        // Upright dimensions after applying preferredTransform (handles 90/180/270 rotation).
        let transformedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let baseWidth = makeEven(max(2, Int( abs(transformedBounds.width).rounded() )))
        let baseHeight = makeEven(max(2, Int( abs(transformedBounds.height).rounded() )))

        let rawFps = nominalFrameRate > 0 ? Int(nominalFrameRate.rounded()) : 30
        let frameRate = min(60, max(15, rawFps))

        let durationSeconds = max(1.0, CMTimeGetSeconds(assetDuration).isFinite ? CMTimeGetSeconds(assetDuration) : 1.0)
        let durationMs = Int64((durationSeconds * 1000.0).rounded())

        // Guard against extreme 5K+ resolutions that exceed mobile hardware codec limits cleanly.
        if max( Int(naturalSize.width), Int(naturalSize.height) ) > 4096 {
            throw TranscodeError(
                "设备硬件编解码器处理失败（分辨率过高或资源不足，源 \(Int(naturalSize.width))x\(Int(naturalSize.height))）"
            )
        }

        // Set up AVAssetWriter and step down resolution if the hardware encoder requires it.
        let writerConfig = try createWriterAndVideoInput(
            outputURL: request.outputURL,
            baseWidth: baseWidth,
            baseHeight: baseHeight,
            frameRate: frameRate
        )
        let writer = writerConfig.writer
        let videoWriterInput = writerConfig.videoInput
        let adaptor = writerConfig.adaptor
        let outputWidth = writerConfig.width
        let outputHeight = writerConfig.height

        // Set up Video AVAssetReader
        let videoReader: AVAssetReader
        do {
            videoReader = try AVAssetReader(asset: asset)
        } catch {
            throw TranscodeError("视频解码器初始化失败", underlying: error)
        }

        let readerPixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: readerPixelBufferAttrs
        )
        videoReaderOutput.alwaysCopiesSampleData = false
        guard videoReader.canAdd(videoReaderOutput) else {
            throw TranscodeError("当前设备不支持解码该视频轨道")
        }
        videoReader.add(videoReaderOutput)

        // Optional Audio passthrough (separate AVAssetReader so video & audio queues never contend)
        var audioReader: AVAssetReader?
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioWriterInput: AVAssetWriterInput?

        if let audioTrack = (try? await asset.loadTracks(withMediaType: .audio))?.first,
           let separateAudioReader = try? AVAssetReader(asset: asset) {
            let formatDescriptions = (try? await audioTrack.load(.formatDescriptions)) ?? []
            let passthroughInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: nil,
                sourceFormatHint: formatDescriptions.first
            )
            passthroughInput.expectsMediaDataInRealTime = false

            if writer.canAdd(passthroughInput) {
                let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
                trackOutput.alwaysCopiesSampleData = false
                if separateAudioReader.canAdd(trackOutput) {
                    separateAudioReader.add(trackOutput)
                    writer.add(passthroughInput)
                    audioReader = separateAudioReader
                    audioReaderOutput = trackOutput
                    audioWriterInput = passthroughInput
                }
            }
        }

        guard videoReader.startReading() else {
            let reason = videoReader.error?.localizedDescription ?? "未知解码错误"
            throw TranscodeError("视频解码器启动失败: \(reason)", underlying: videoReader.error)
        }
        if let aReader = audioReader, !aReader.startReading() {
            // Degrade gracefully to silent video if audio track fails to start reading.
            audioReader = nil
            audioReaderOutput = nil
            audioWriterInput = nil
        }

        guard writer.startWriting() else {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            let reason = writer.error?.localizedDescription ?? "未知编码错误"
            throw TranscodeError("视频编码器启动失败: \(reason)", underlying: writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ciContext: CIContext
        if let mtlDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(
                mtlDevice: mtlDevice,
                options: [
                    .workingColorSpace: colorSpace,
                    .outputColorSpace: colorSpace,
                    .cacheIntermediates: false
                ]
            )
        } else {
            ciContext = CIContext(
                options: [
                    .workingColorSpace: colorSpace,
                    .outputColorSpace: colorSpace,
                    .useSoftwareRenderer: true,
                    .cacheIntermediates: false
                ]
            )
        }

        // Pump video and audio concurrently via AVFoundation backpressure queues
        let pumpOutcome = await pumpSamples(
            videoReader: videoReader,
            videoReaderOutput: videoReaderOutput,
            videoWriterInput: videoWriterInput,
            adaptor: adaptor,
            audioReader: audioReader,
            audioReaderOutput: audioReaderOutput,
            audioWriterInput: audioWriterInput,
            preferredTransform: preferredTransform,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            durationSeconds: durationSeconds,
            ciContext: ciContext,
            colorSpace: colorSpace,
            onProgress: onProgress
        )

        if cancelFlag.isCancelled {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            writer.cancelWriting()
            throw TranscodeCancelledError()
        }

        if let pumpError = pumpOutcome.error {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            writer.cancelWriting()
            throw pumpError
        }

        if videoReader.status == .failed {
            audioReader?.cancelReading()
            writer.cancelWriting()
            throw TranscodeError(
                "设备硬件解码失败: \(videoReader.error?.localizedDescription ?? "未知错误")",
                underlying: videoReader.error
            )
        }

        guard pumpOutcome.frameCount > 0 else {
            writer.cancelWriting()
            throw TranscodeError("没有产生任何视频帧")
        }

        await finishWriter(writer)

        if cancelFlag.isCancelled {
            throw TranscodeCancelledError()
        }

        if writer.status != .completed {
            throw TranscodeError(
                "封装输出视频失败: \(writer.error?.localizedDescription ?? "未知错误")",
                underlying: writer.error
            )
        }

        onProgress(1.0)
        return TranscodeResult(
            outputURL: request.outputURL,
            width: outputWidth,
            height: outputHeight,
            durationMs: durationMs,
            frameCount: pumpOutcome.frameCount
        )
    }

    // MARK: - Sample Pumping & GPU Overlay Composition

    private struct PumpOutcome: Sendable {
        let frameCount: Int64
        let error: TranscodeError?
    }

    private struct SerialQueueBox<T>: @unchecked Sendable {
        let value: T
    }

    private func pumpSamples(
        videoReader: AVAssetReader,
        videoReaderOutput: AVAssetReaderTrackOutput,
        videoWriterInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        audioReader: AVAssetReader?,
        audioReaderOutput: AVAssetReaderTrackOutput?,
        audioWriterInput: AVAssetWriterInput?,
        preferredTransform: CGAffineTransform,
        outputWidth: Int,
        outputHeight: Int,
        durationSeconds: Double,
        ciContext: CIContext,
        colorSpace: CGColorSpace,
        onProgress: @escaping @Sendable (Float) -> Void
    ) async -> PumpOutcome {
        await withCheckedContinuation { continuation in
            let group = DispatchGroup()
            let videoQueue = DispatchQueue(label: "com.teslacam.timestamp.video", qos: .userInitiated)
            let audioQueue = DispatchQueue(label: "com.teslacam.timestamp.audio", qos: .userInitiated)

            let stateLock = NSLock()
            var totalFrames: Int64 = 0
            var capturedError: TranscodeError?

            // Cached overlay CIImage (rebuilt only once per second when timestamp string changes)
            var cachedOverlayKey: String?
            var cachedPlacedOverlay: CIImage?
            var firstPtsSeconds: Double?

            let outputRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
            let style = request.style

            // 1. Video Pump (all video AVFoundation objects are accessed exclusively on `videoQueue`)
            let vInputBox = SerialQueueBox(value: videoWriterInput)
            let vOutputBox = SerialQueueBox(value: videoReaderOutput)
            let adaptorBox = SerialQueueBox(value: adaptor)
            let ciContextBox = SerialQueueBox(value: ciContext)

            group.enter()
            var videoFinished = false
            videoWriterInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
                let vInput = vInputBox.value
                let vOutput = vOutputBox.value
                let vAdaptor = adaptorBox.value
                let vCIContext = ciContextBox.value

                guard let self else {
                    if !videoFinished {
                        videoFinished = true
                        vInput.markAsFinished()
                        group.leave()
                    }
                    return
                }
                if videoFinished { return }

                while vInput.isReadyForMoreMediaData {
                    var shouldStop = false
                    autoreleasepool {
                        if self.cancelFlag.isCancelled {
                            shouldStop = true
                            return
                        }

                        guard let sampleBuffer = vOutput.copyNextSampleBuffer() else {
                            shouldStop = true
                            return
                        }

                        guard let srcPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                            return
                        }

                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let rawPtsSec = CMTimeGetSeconds(pts)
                        let validPtsSec = rawPtsSec.isFinite ? rawPtsSec : 0.0
                        if firstPtsSeconds == nil {
                            firstPtsSeconds = max(0.0, min(validPtsSec, 0.5))
                        }
                        let elapsedSec = max(0.0, validPtsSec - (firstPtsSeconds ?? 0.0))
                        let elapsedMs = Int64((elapsedSec * 1000.0).rounded(.down))
                        let wallClockMs = self.request.startEpochMillis + elapsedMs

                        // Build upright, scaled video CIImage
                        let videoImage = Self.orientAndScale(
                            pixelBuffer: srcPixelBuffer,
                            preferredTransform: preferredTransform,
                            outputWidth: outputWidth,
                            outputHeight: outputHeight
                        )

                        // Update overlay texture only when text changes (once per second)
                        let lines = self.buildOverlayLines(wallClockMs: wallClockMs, style: style)
                        let key = "\(lines.joined(separator: "\n"))|\(style.position.rawValue)|\(style.textScale)|\(outputWidth)x\(outputHeight)|\(Int(style.boxAlpha * 100))"
                        if key != cachedOverlayKey {
                            let textSizePx = max(10.0, CGFloat(outputHeight) * CGFloat(style.textFraction))
                            if let cgOverlay = OverlayBitmapFactory.create(
                                lines: lines,
                                textSizePx: textSizePx,
                                style: style
                            ) {
                                let origin = OverlayBitmapFactory.originInBottomUpCanvas(
                                    canvasWidth: outputWidth,
                                    canvasHeight: outputHeight,
                                    overlayWidth: cgOverlay.width,
                                    overlayHeight: cgOverlay.height,
                                    minMargin: 4,
                                    style: style
                                )
                                cachedPlacedOverlay = CIImage(cgImage: cgOverlay).transformed(
                                    by: CGAffineTransform(translationX: CGFloat(origin.x), y: CGFloat(origin.y))
                                )
                                cachedOverlayKey = key
                            }
                        }

                        let composited: CIImage
                        if let overlay = cachedPlacedOverlay {
                            composited = overlay.composited(over: videoImage).cropped(to: outputRect)
                        } else {
                            composited = videoImage.cropped(to: outputRect)
                        }

                        var dstBufferOut: CVPixelBuffer?
                        let status: CVReturn
                        if let pool = vAdaptor.pixelBufferPool {
                            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dstBufferOut)
                        } else {
                            let attrs: [CFString: Any] = [
                                kCVPixelBufferCGImageCompatibilityKey: true,
                                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                                kCVPixelBufferMetalCompatibilityKey: true
                            ]
                            status = CVPixelBufferCreate(
                                kCFAllocatorDefault,
                                outputWidth,
                                outputHeight,
                                kCVPixelFormatType_32BGRA,
                                attrs as CFDictionary,
                                &dstBufferOut
                            )
                        }
                        guard status == kCVReturnSuccess, let dstPixelBuffer = dstBufferOut else {
                            stateLock.lock()
                            capturedError = TranscodeError("无法分配输出帧内存 (\(status))")
                            stateLock.unlock()
                            shouldStop = true
                            return
                        }

                        vCIContext.render(
                            composited,
                            to: dstPixelBuffer,
                            bounds: outputRect,
                            colorSpace: colorSpace
                        )

                        if !vAdaptor.append(dstPixelBuffer, withPresentationTime: pts) {
                            stateLock.lock()
                            capturedError = TranscodeError("写入编码视频帧失败")
                            stateLock.unlock()
                            shouldStop = true
                            return
                        }

                        stateLock.lock()
                        totalFrames += 1
                        stateLock.unlock()

                        let fraction = Float(min(0.99, max(0.0, elapsedSec / durationSeconds)))
                        onProgress(fraction)
                    }

                    if shouldStop {
                        videoFinished = true
                        vInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            // 2. Audio Passthrough Pump (accessed exclusively on `audioQueue`)
            if let aInput = audioWriterInput, let aOutput = audioReaderOutput {
                let aInputBox = SerialQueueBox(value: aInput)
                let aOutputBox = SerialQueueBox(value: aOutput)
                group.enter()
                var audioFinished = false
                aInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
                    let audioIn = aInputBox.value
                    let audioOut = aOutputBox.value
                    if audioFinished { return }
                    while audioIn.isReadyForMoreMediaData {
                        if self?.cancelFlag.isCancelled == true {
                            audioFinished = true
                            audioIn.markAsFinished()
                            group.leave()
                            return
                        }
                        guard let sample = audioOut.copyNextSampleBuffer() else {
                            audioFinished = true
                            audioIn.markAsFinished()
                            group.leave()
                            return
                        }
                        if !audioIn.append(sample) {
                            audioFinished = true
                            audioIn.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            } else {
                _ = audioReader
            }

            group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                stateLock.lock()
                let outcome = PumpOutcome(frameCount: totalFrames, error: capturedError)
                stateLock.unlock()
                continuation.resume(returning: outcome)
            }
        }
    }

    /// Converts a decoded `CVPixelBuffer` (CoreImage bottom-up coordinates) with an AVAssetTrack
    /// `preferredTransform` (QuickTime top-down coordinates) into an upright `CIImage` filling `(0, 0, outputWidth, outputHeight)`.
    static func orientAndScale(
        pixelBuffer: CVPixelBuffer,
        preferredTransform: CGAffineTransform,
        outputWidth: Int,
        outputHeight: Int
    ) -> CIImage {
        orientAndScale(
            image: CIImage(cvPixelBuffer: pixelBuffer),
            preferredTransform: preferredTransform,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )
    }

    static func orientAndScale(
        image baseImage: CIImage,
        preferredTransform: CGAffineTransform,
        outputWidth: Int,
        outputHeight: Int
    ) -> CIImage {
        let srcW = baseImage.extent.width
        let srcH = baseImage.extent.height
        guard srcW > 0 && srcH > 0 else { return baseImage }

        let combined = uprightTransform(
            srcWidth: srcW,
            srcHeight: srcH,
            preferredTransform: preferredTransform,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )

        var transformed = baseImage.transformed(by: combined)
        if transformed.extent.origin != .zero {
            transformed = transformed.transformed(
                by: CGAffineTransform(
                    translationX: -transformed.extent.origin.x,
                    y: -transformed.extent.origin.y
                )
            )
        }
        return transformed
    }

    static func uprightTransform(
        srcWidth srcW: CGFloat,
        srcHeight srcH: CGFloat,
        preferredTransform: CGAffineTransform,
        outputWidth: Int,
        outputHeight: Int
    ) -> CGAffineTransform {
        // 1. Convert CoreImage bottom-up -> QuickTime top-down
        let ciToQT = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: srcH)

        // 2. Apply track's preferredTransform in QuickTime space and normalize origin to (0, 0)
        let qtRect = CGRect(x: 0, y: 0, width: srcW, height: srcH).applying(preferredTransform)
        let uprightW = max(1.0, abs(qtRect.width))
        let uprightH = max(1.0, abs(qtRect.height))
        let normalizeQT = preferredTransform.concatenating(
            CGAffineTransform(translationX: -qtRect.origin.x, y: -qtRect.origin.y)
        )

        // 3. Convert QuickTime top-down -> CoreImage bottom-up in upright space
        let qtToCI = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: uprightH)

        // 4. Scale to exact encoder output dimensions
        let scale = CGAffineTransform(
            scaleX: CGFloat(outputWidth) / uprightW,
            y: CGFloat(outputHeight) / uprightH
        )

        return ciToQT
            .concatenating(normalizeQT)
            .concatenating(qtToCI)
            .concatenating(scale)
    }

    private func buildOverlayLines(wallClockMs: Int64, style: OverlayStyle) -> [String] {
        let first = OverlayText.firstLine(wallClockMs, style: style, timeZone: request.timeZone)
        let details = style.showDetails ? request.detailText : nil
        if let details = details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            return [first, details]
        }
        return [first]
    }

    // MARK: - Encoder Setup & Resolution Fallback

    private struct WriterSetup {
        let writer: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let width: Int
        let height: Int
    }

    private func createWriterAndVideoInput(
        outputURL: URL,
        baseWidth: Int,
        baseHeight: Int,
        frameRate: Int
    ) throws -> WriterSetup {
        var candidateWidth = baseWidth
        var candidateHeight = baseHeight
        var attempt = 0
        var lastError: Error?

        while attempt < 6 && candidateWidth >= 320 && candidateHeight >= 240 {
            do {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                writer.shouldOptimizeForNetworkUse = true

                let bitRate = estimateBitRate(
                    width: candidateWidth,
                    height: candidateHeight,
                    frameRate: frameRate
                )
                let compressionProps: [String: Any] = [
                    AVVideoAverageBitRateKey: bitRate,
                    AVVideoExpectedSourceFrameRateKey: frameRate,
                    AVVideoMaxKeyFrameIntervalKey: frameRate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
                let outputSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: candidateWidth,
                    AVVideoHeightKey: candidateHeight,
                    AVVideoCompressionPropertiesKey: compressionProps
                ]

                if writer.canApply(outputSettings: outputSettings, forMediaType: .video) {
                    let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
                    input.expectsMediaDataInRealTime = false

                    let poolAttrs: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                        kCVPixelBufferWidthKey as String: candidateWidth,
                        kCVPixelBufferHeightKey as String: candidateHeight,
                        kCVPixelBufferMetalCompatibilityKey as String: true
                    ]
                    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                        assetWriterInput: input,
                        sourcePixelBufferAttributes: poolAttrs
                    )
                    if writer.canAdd(input) {
                        writer.add(input)
                        return WriterSetup(
                            writer: writer,
                            videoInput: input,
                            adaptor: adaptor,
                            width: candidateWidth,
                            height: candidateHeight
                        )
                    }
                }
            } catch {
                lastError = error
            }

            let nextWidth = align16(candidateWidth * 3 / 4)
            let nextHeight = align16(candidateHeight * 3 / 4)
            if nextWidth == candidateWidth && nextHeight == candidateHeight { break }
            candidateWidth = nextWidth
            candidateHeight = nextHeight
            attempt += 1
        }

        throw TranscodeError(
            "当前设备无法编码该分辨率（源 \(baseWidth)x\(baseHeight)）",
            underlying: lastError
        )
    }

    private func finishWriter(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    private func makeEven(_ value: Int) -> Int {
        value % 2 == 0 ? value : value - 1
    }

    private func align16(_ value: Int) -> Int {
        max(16, (value / 16) * 16)
    }

    private func estimateBitRate(width: Int, height: Int, frameRate: Int) -> Int {
        let bitsPerSecond = Int64(width) * Int64(height) * Int64(frameRate) * 9 / 100
        let clamped = min(24_000_000, max(3_000_000, bitsPerSecond))
        return Int(clamped)
    }
}
