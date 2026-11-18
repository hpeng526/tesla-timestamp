import AVFoundation
import Foundation

/// Public entry point of the compositing pipeline. One instance handles one clip at a time and can
/// be cancelled safely from any thread or Swift Concurrency task.
public final class TimestampVideoProcessor: @unchecked Sendable {

    private let lock = NSLock()
    private var active: TimestampTranscoder?

    public init() {}

    public func cancel() {
        currentActive()?.cancel()
    }

    /// Runs the whole pipeline and writes the timestamped MP4 to `request.outputURL`.
    /// Removes partially written output files on cancellation or error.
    public func process(
        _ request: TranscodeRequest,
        onProgress: @escaping @Sendable (Float) -> Void = { _ in }
    ) async throws -> TranscodeResult {
        let outputURL = request.outputURL
        let parentDir = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let transcoder = TimestampTranscoder(request: request)
        setActive(transcoder)
        defer { clearActive(ifMatching: transcoder) }

        do {
            return try await transcoder.transcode(onProgress: onProgress)
        } catch let cancelled as TranscodeCancelledError {
            try? FileManager.default.removeItem(at: outputURL)
            throw cancelled
        } catch is CancellationError {
            transcoder.cancel()
            try? FileManager.default.removeItem(at: outputURL)
            throw TranscodeCancelledError()
        } catch let transcodeError as TranscodeError {
            try? FileManager.default.removeItem(at: outputURL)
            throw transcodeError
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw TranscodeError(Self.describe(error), underlying: error)
        }
    }

    private func currentActive() -> TimestampTranscoder? {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    private func setActive(_ transcoder: TimestampTranscoder) {
        lock.lock()
        active = transcoder
        lock.unlock()
    }

    private func clearActive(ifMatching transcoder: TimestampTranscoder) {
        lock.lock()
        if active === transcoder {
            active = nil
        }
        lock.unlock()
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            return "设备硬件编解码器处理失败（错误码 \(nsError.code)）"
        }
        let message = error.localizedDescription
        return message.isEmpty ? "视频处理失败" : message
    }
}
